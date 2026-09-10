"""ARIA — generic web-research browser agent built on the vendored browser-use.

Every web-research task from the Agent Hub runs through here. The ARIA brain
(services/aria_brain.py) classifies each task, keeps the user's raw query
verbatim, and routes it across two tools:

* Firecrawl (vendored SDK) — fast web research phase: search + targeted scrapes.
* browser-use (vendored)   — real (visible, local) browser execution.

The flow is: plan → (research) → browse → evidence → synthesis. It streams each
browser/research step to Flutter as it happens and finishes with a ``content``
answer plus ``done``, where the answer is a real synthesis of the collected
evidence — never just "Completed". Cancellation works the same way as the
commerce flow (flag + tracked asyncio task + browser cleanup).
"""

from __future__ import annotations

import asyncio
import logging
import os
from typing import Callable, Optional
from uuid import uuid4

from config import Settings
from vendor_browser_use import bootstrap_vendored_browser_use, IS_VENDORED_PRESENT

bootstrap_vendored_browser_use()

from browser_use import Agent, BrowserSession, BrowserProfile, ChatGoogle, ChatGroq  # noqa: E402

from pydantic_models.aria_models import AriaEvidence, AriaPlan  # noqa: E402
from services.aria_brain import (  # noqa: E402
    AriaBrain,
    dedupe_sources,
    extract_domains,
    research_enabled,
    should_stop_research,
    synthesize_answer,
)
from services.firecrawl_service import FirecrawlError, FirecrawlService  # noqa: E402

logger = logging.getLogger(__name__)


def get_settings() -> Settings:
    return Settings()


def _playwright_importable() -> bool:
    try:
        import playwright  # noqa: F401
        return True
    except Exception:
        return False


def _browser_headless() -> bool:
    return bool((os.getenv("BROWSER_USE_HEADLESS") or "").strip())


_GOOGLE_DOMAINS = frozenset({
    'google.com', 'www.google.com', 'google.co.in', 'www.google.co.in',
    'google.co.uk', 'www.google.co.uk',
})


def _extract_domains_from_query(query: str) -> list[str]:
    """Return all host-only domains found in the raw query (shared ARIA helper)."""
    return extract_domains(query)


def _build_task_prompt(query: str) -> str:
    """Return the browser-use task prompt using the user's query verbatim."""
    return f"""You are ARIA, an autonomous web browser agent running inside a real browser.

TASK (execute this EXACTLY, do not reinterpret it):
{query}

GUIDELINES:
1. Observe the actual rendered page before deciding what to do next.
2. If a website/domain is mentioned, navigate there directly.
3. Search the web when the task needs information you don't have yet.
4. Read pages thoroughly, extract the information the user asked for.
5. Interact with the page (click, type, scroll) as needed to complete the task.
6. Verify important actions actually worked before moving on.
7. Stop once the user's request has been satisfied.

FINAL ANSWER: Report the actual result you observed, with source URLs. Do not fabricate.
"""


# ------------------------------------------------------------------
# Domain expansion for allowed_domains
# ------------------------------------------------------------------

def _extra_domains_for_query(query: str, base_allowed: list[str]) -> list[str]:
    """Extract domains from the query and return extra allowed-domain entries."""
    extra: list[str] = []
    for d in _extract_domains_from_query(query):
        if d in _GOOGLE_DOMAINS:
            continue
        already = d in base_allowed or f'*.{d}' in base_allowed
        if not already:
            extra.append(d)
            extra.append(f'*.{d}')
    return extra


class BrowserAgentService:
    """Runs one web-research browser-use agent per task and streams live events."""

    def __init__(self) -> None:
        self.active_tasks: dict[str, bool] = {}
        self.background_tasks: dict[str, asyncio.Task] = {}
        self.browser_sessions: dict[str, list] = {}
        self.llm = None
        self.fallback_llm = None
        self._provider: Optional[str] = None
        self._model: Optional[str] = None
        self._initialize_llm()
        self._firecrawl = FirecrawlService()
        self.brain = AriaBrain(plan_llm=self._make_plan_callable())

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    @property
    def is_ready(self) -> bool:
        """True when an LLM provider is configured so the agent can actually run."""
        return self.llm is not None

    def _initialize_llm(self) -> None:
        settings = get_settings()
        self.fallback_llm = None
        try:
            if settings.GEMINI_API_KEY:
                self.llm = ChatGoogle(
                    model="gemini-3.1-flash-lite",
                    api_key=settings.GEMINI_API_KEY,
                    temperature=0.0,
                )
                self._provider, self._model = "gemini", "gemini-3.1-flash-lite"
                logger.info("✅ Browser agent initialized with Gemini (primary)")
                if settings.GROQ_API_KEY:
                    try:
                        self.fallback_llm = ChatGroq(
                            model="openai/gpt-oss-120b",
                            api_key=settings.GROQ_API_KEY,
                            temperature=0.0,
                        )
                        logger.info("✅ Browser agent fallback LLM initialized with Groq")
                    except Exception as exc:  # pragma: no cover - env dependent
                        logger.warning(f"❌ Groq fallback LLM init failed: {exc}")
                return
            if settings.GROQ_API_KEY:
                self.llm = ChatGroq(
                    model="openai/gpt-oss-120b",
                    api_key=settings.GROQ_API_KEY,
                    temperature=0.0,
                )
                self._provider, self._model = "groq", "openai/gpt-oss-120b"
                logger.info("✅ Browser agent initialized with Groq")
                return
        except Exception as e:  # pragma: no cover - env dependent
            logger.error(f"Failed to initialize browser agent LLM: {e}")
        self.llm = None

    def _create_browser_session(
        self, task_id: str, extra_domains: list[str] | None = None,
    ) -> BrowserSession:
        # No allowed_domains restriction → browser-use Security Watchdog allows
        # navigation to ANY site the agent needs (watchdog allows all when the
        # allowlist is None). Remove/keep the extra_domains param for callers.
        allowed_domains: list[str] | None = None
        if extra_domains:
            allowed_domains = list(extra_domains)

        browser_profile = BrowserProfile(
            headless=os.getenv("BROWSER_USE_HEADLESS", "") or None,
            allowed_domains=allowed_domains,
            minimum_wait_page_load_time=0.2,
            wait_between_actions=0.2,
            keep_alive=False,
        )
        return BrowserSession(
            browser_profile=browser_profile,
            allowed_domains=allowed_domains,
            keep_alive=False,
            user_data_dir=None,
            use_cloud=False,
        )

    async def _send_event(self, event_callback: Callable, payload: dict) -> None:
        try:
            if event_callback:
                await event_callback(payload)
        except Exception as e:
            logger.error(f"Failed to send browse event: {e}")

    def _is_safe_message(self, message: str) -> bool:
        """Reject messages that expose internal implementation details."""
        if not message:
            return False
        msg = message.lower()
        blocked = [
            "reasoning step", "action_items",
            "selector", "xpath", "backend_node", "evaluate_previous_goal",
        ]
        return not any(b in msg for b in blocked)

    # ------------------------------------------------------------------
    # ARIA brain (planning + Firecrawl research)
    # ------------------------------------------------------------------

    def _make_plan_callable(self):
        """Adapt the browser agent's LLM into a ``prompt -> text`` callable for the brain."""
        async def plan_callable(prompt: str) -> str:
            if self.llm is None:
                raise RuntimeError("browser agent LLM is not initialized")
            from browser_use.llm.messages import SystemMessage, UserMessage
            response = await self.llm.ainvoke([
                SystemMessage(content=(
                    "You are a strict JSON planner. Output ONLY the JSON object, "
                    "no prose, no markdown fences."
                )),
                UserMessage(content=prompt),
            ])
            return getattr(response, "completion", "") or ""
        return plan_callable

    async def _build_plan(self, query: str) -> tuple:
        """Build the ARIA plan; never lets a planner failure block the task."""
        try:
            if self.llm is not None:
                # Bound planning so a slow/hung LLM cannot stall the browse task.
                return await asyncio.wait_for(
                    self.brain.build_plan(query, allow_llm=True), timeout=20,
                )
            return await self.brain.build_plan(query, allow_llm=False)
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning(f"[ARIA DECISION] brain planning failed ({exc}); using fallback")
            return await self.brain.build_plan(query, allow_llm=False)

    async def _run_firecrawl_research(
        self,
        raw_query: str,
        plan: AriaPlan,
        evidence: list[AriaEvidence],
        collected_text: list[str],
        collected_urls: list[str],
        event_callback: Optional[Callable],
        task_id: str,
    ) -> bool:
        """Firecrawl research phase: search, dedupe sources, scrape a few pages.

        Runs only when the plan routes to ``firecrawl``. Any failure degrades
        gracefully to browser-only research instead of aborting the task.
        """
        if not self._firecrawl.is_available:
            logger.info(
                "[ARIA DECISION] Firecrawl not configured/SDK missing -> research via browser only"
            )
            return False

        seen_urls: set[str] = set()
        seen_domains: list[str] = []
        search_budget = min(plan.budget.get("firecrawl_search", 6), 8)
        scrape_budget = plan.budget.get("firecrawl_scrape", 2)

        await self._send_event(event_callback, {
            "type": "aria_tool",
            "task_id": task_id,
            "tool": "firecrawl",
            "op": "search",
            "query": raw_query,
            "domains": plan.target_domains,
        })

        try:
            results = await self._firecrawl.search_web(
                raw_query,
                include_domains=plan.target_domains or None,
                limit=search_budget,
            )
        except FirecrawlError as exc:
            logger.warning(f"[ARIA FIRECRAWL] search unavailable: {exc}")
            return False

        if not results:
            logger.info("[ARIA FIRECRAWL] no results -> research via browser only")
            return False

        selected = dedupe_sources(results, seen_urls, seen_domains, cap_per_domain=2)
        for r in selected[:search_budget]:
            ev = AriaEvidence(
                source="firecrawl",
                url=r["url"],
                domain=r["domain"],
                title=r.get("title"),
                content=(r.get("content") or None),
                kind="search",
            )
            evidence.append(ev)
            if r.get("content"):
                collected_text.append(f"[{r['domain']}] {r['content']}")
            if r["url"] not in collected_urls:
                collected_urls.append(r["url"])
            await self._send_event(event_callback, {
                "type": "aria_evidence",
                "task_id": task_id,
                "source": "firecrawl",
                "kind": "search",
                "domain": r["domain"],
                "url": r["url"],
                "title": r.get("title"),
            })
            if should_stop_research(len(evidence)):
                break

        # Enrich the top unique sources with page scrapes (within budget).
        scraped = 0
        for r in selected:
            if scraped >= scrape_budget:
                break
            if should_stop_research(len(evidence)):
                break
            if not r.get("url"):
                continue
            try:
                doc = await self._firecrawl.scrape_url(r["url"])
            except FirecrawlError as exc:
                logger.warning(f"[ARIA FIRECRAWL] scrape failed {r['url']}: {exc}")
                continue
            content = doc.get("content") or ""
            if not content:
                continue
            evidence.append(AriaEvidence(
                source="firecrawl",
                url=r["url"],
                domain=r["domain"],
                title=doc.get("title") or r.get("title"),
                content=content[:1500],
                kind="page",
            ))
            if r["url"] not in collected_urls:
                collected_urls.append(r["url"])
            collected_text.append(f"[{r['domain']}] {content[:1000]}")
            scraped += 1
            await self._send_event(event_callback, {
                "type": "aria_evidence",
                "task_id": task_id,
                "source": "firecrawl",
                "kind": "page",
                "domain": r["domain"],
                "url": r["url"],
            })

        logger.info(f"[ARIA EVIDENCE] firecrawl research -> {len(evidence)} pieces")
        return len(evidence) > 0

    # ------------------------------------------------------------------
    # Main run
    # ------------------------------------------------------------------

    async def start_browser_task(
        self,
        query: str,
        event_callback: Optional[Callable] = None,
        task_id: Optional[str] = None,
    ) -> str:
        """Run a full web-research browser task for ``query`` and stream events live."""
        headless = _browser_headless()
        logger.info(
            "[ARIA RUNTIME] vendored=%s playwright=%s llm=%s provider=%s model=%s "
            "fallback_browser_llm=%s headless=%s",
            IS_VENDORED_PRESENT, _playwright_importable(), self.llm is not None,
            self._provider, self._model, self.fallback_llm is not None, headless,
        )
        if not IS_VENDORED_PRESENT:
            await self._send_event(event_callback, {
                "type": "error", "task_id": task_id or "error",
                "message": (
                    "The vendored browser-use folder was not found at "
                    "<repo>/browser-use. The browser agent cannot start."
                ),
                "error_type": "ImportError",
            })
            return task_id or "error"

        if not self.llm:
            await self._send_event(event_callback, {
                "type": "error", "task_id": task_id or "error",
                "message": (
                    "No LLM provider is configured for the browser agent. Set "
                    "GEMINI_API_KEY or GROQ_API_KEY in the backend .env."
                ),
                "error_type": "ConfigurationError",
            })
            return task_id or "error"

        try:
            import playwright  # noqa: F401
        except ImportError:
            await self._send_event(event_callback, {
                "type": "error", "task_id": task_id or "error",
                "message": (
                    "Playwright is not installed in the backend environment. "
                    "Run:  pip install playwright && playwright install chromium"
                ),
                "error_type": "ImportError",
            })
            return task_id or "error"

        if task_id is None:
            task_id = str(uuid4())
        logger.info("[ARIA BROWSER_INIT] available=%s provider=%s model=%s playwright=%s", 
                    self.is_ready, self._provider, self._model, _playwright_importable())
        self.active_tasks[task_id] = True
        self.background_tasks.setdefault(task_id, None)

        # --- plan the task with the ARIA brain (raw query is NEVER rewritten) ---
        user_task, plan = await self._build_plan(query)
        task_prompt = _build_task_prompt(user_task.raw_query)
        extra_domains = _extra_domains_for_query(user_task.raw_query, [])
        logger.info(
            "[ARIA BROWSER_TASK] raw_query=%r browser_task=%r task_preserved=%s",
            user_task.raw_query, task_prompt[:120],
            user_task.raw_query in task_prompt,
        )

        await self._send_event(event_callback, {
            "type": "aria_plan",
            "task_id": task_id,
            "intent": plan.intent,
            "tools": plan.tools,
            "focus": plan.focus,
            "target_domains": plan.target_domains,
        })

        # --- initial navigation if the query names a domain ---
        initial_actions = None
        nav_domain = None
        for d in list(plan.target_domains) + _extract_domains_from_query(user_task.raw_query):
            if d not in _GOOGLE_DOMAINS:
                nav_domain = d
                break
        if nav_domain:
            url = nav_domain if nav_domain.startswith('http') else f'https://{nav_domain}'
            initial_actions = [{'navigate': {'url': url, 'new_tab': False}}]
            logger.info(f"[ARIA BROWSER_NAV] url={url} domain={nav_domain}")

        browser_session = None
        collected_text: list[str] = []
        collected_steps: list[str] = []
        collected_urls: list[str] = []
        visited_domains: set[str] = set()
        evidence: list[AriaEvidence] = []
        tools_used: list[str] = []

        # --- Firecrawl research phase (hybrid routing: facts first, browser next) ---
        if research_enabled(plan):
            try:
                research_ok = await self._run_firecrawl_research(
                    user_task.raw_query,
                    plan,
                    evidence,
                    collected_text,
                    collected_urls,
                    event_callback,
                    task_id,
                )
            except Exception as exc:  # best-effort phase; browser still runs
                logger.error(f"[ARIA FIRECRAWL] research phase failed: {exc}")
                research_ok = False
            if research_ok:
                tools_used.append("firecrawl")

        async def should_stop_callback() -> bool:
            return not self.active_tasks.get(task_id, False)

        async def step_callback(state_summary, agent_output, step_number):
            if not self.active_tasks.get(task_id, False):
                return
            try:
                memory = getattr(agent_output, "memory", None)
                if memory:
                    collected_text.append(str(memory))
                next_goal = getattr(agent_output, "next_goal", None) or ""
                cur_url = getattr(state_summary, "url", None) or None
                title = getattr(state_summary, "title", None) or None

                if cur_url:
                    if cur_url not in collected_urls:
                        collected_urls.append(cur_url)
                    try:
                        from urllib.parse import urlparse
                        dom = urlparse(cur_url).netloc.lower()
                        if dom:
                            visited_domains.add(dom)
                            if len(collected_urls) <= 1 or dom not in visited_domains:
                                logger.info(f"[ARIA SOURCE] Visited: {dom}")
                    except Exception:
                        pass

                if next_goal and self._is_safe_message(next_goal):
                    if next_goal not in collected_steps:
                        collected_steps.append(next_goal)
                    await self._send_event(event_callback, {
                        "type": "agent_step",
                        "task_id": task_id,
                        "message": next_goal,
                        "url": cur_url,
                        "title": title,
                        "step_number": step_number,
                    })

                logger.info(
                    f"[ARIA STEP] step={step_number} "
                    f"urls={len(collected_urls)} domains={len(visited_domains)}"
                )
            except Exception as e:
                logger.warning(f"browse step callback error: {e}")

        try:
            browser_session = self._create_browser_session(task_id, extra_domains)
            self.browser_sessions.setdefault(task_id, []).append(browser_session)

            agent = Agent(
                task=task_prompt,
                llm=self.llm,
                fallback_llm=self.fallback_llm,
                browser_session=browser_session,
                max_actions_per_step=5,
                max_failures=3,
                task_id=task_id,
                register_should_stop_callback=should_stop_callback,
                register_new_step_callback=step_callback,
                loop_detection_enabled=True,
                step_timeout=180,
                initial_actions=initial_actions,
            )
            logger.info(
                "[ARIA BROWSER_ACTION] task=%s agent_started=true "
                "fallback_llm_active=false max_steps=50 step_timeout=180",
                task_id,
            )

            timed_out = False
            try:
                history = await asyncio.wait_for(
                    agent.run(max_steps=50), timeout=180,
                )
            except asyncio.TimeoutError:
                logger.warning(f"[browse] task {task_id} timed out; returning partial result.")
                history = agent.history if hasattr(agent, "history") else None
                timed_out = True

            # --- build the final answer from browser outputs ---
            final_parts: list[str] = []
            if history:
                if hasattr(history, "final_result"):
                    try:
                        fr = history.final_result() or ""
                        if fr and fr.strip():
                            final_parts.append(fr.strip())
                    except Exception:
                        pass
                if hasattr(history, "extracted_content"):
                    try:
                        extracted = history.extracted_content() or []
                        for piece in extracted:
                            piece = (piece or "").strip()
                            if piece and piece not in final_parts:
                                final_parts.append(piece)
                    except Exception:
                        pass

            answer = "\n\n".join(p for p in final_parts if p).strip()

            # --- final synthesis: combine browser output + Firecrawl evidence ---
            # Guarantee: the user gets a real, sourced answer — never just "Completed".
            answer = synthesize_answer(
                answer, evidence, collected_steps, collected_urls,
                timed_out=timed_out,
            )
            tools_used.append("browser")

            logger.info(
                "[ARIA BROWSER_RESULT] success=%s result_available=%s "
                "final_present=%s steps=%s urls=%s domains=%s timed_out=%s fallback_used=%s",
                bool(answer), bool(answer), bool(final_parts),
                len(collected_steps), len(collected_urls), len(visited_domains),
                timed_out,
                getattr(agent, "is_using_fallback_llm", False),
            )

            logger.info(
                f"[ARIA SYNTHESIS] evidence={len(evidence)} urls={len(collected_urls)} "
                f"tools={tools_used}"
            )
            logger.info(f"[ARIA FINAL] answer={len(answer)} chars")
            await self._send_event(event_callback, {
                "type": "aria_synthesis",
                "task_id": task_id,
                "summary_chars": len(answer),
                "evidence_count": len(evidence),
                "tools_used": tools_used,
                "timed_out": timed_out,
            })

            n_steps = len(collected_steps)
            n_urls = len(collected_urls)
            await self._send_event(event_callback, {
                "type": "content",
                "data": answer,
            })
            await self._send_event(event_callback, {
                "type": "done",
                "task_id": task_id,
                "timed_out": timed_out,
                "total_steps": n_steps,
                "visited_urls": n_urls,
                "evidence_count": len(evidence),
                "tools_used": tools_used,
            })
            return task_id
        except asyncio.CancelledError:
            self.active_tasks[task_id] = False
            raise
        except Exception as e:
            self.active_tasks[task_id] = False
            logger.error(f"[ARIA ERROR] task {task_id} failed: {e}", exc_info=True)
            await self._send_event(event_callback, {
                "type": "error",
                "task_id": task_id,
                "message": f"Browser agent error: {e}",
                "error_type": type(e).__name__,
            })
            return task_id
        finally:
            self.active_tasks[task_id] = False
            await self._cleanup_browser_sessions(task_id)

    async def cancel_task(self, task_id: str, event_callback: Optional[Callable] = None) -> bool:
        """Stop a running browser task and confirm it to the client."""
        if task_id not in self.active_tasks:
            return False
        self.active_tasks[task_id] = False

        bg = self.background_tasks.get(task_id)
        if bg is not None and not bg.done():
            bg.cancel()

        await self._cleanup_browser_sessions(task_id)
        self.background_tasks.pop(task_id, None)

        await self._send_event(event_callback, {
            "type": "browse_cancelled",
            "task_id": task_id,
            "success": True,
        })
        return True

    async def _cleanup_browser_sessions(self, task_id: str) -> None:
        sessions = self.browser_sessions.pop(task_id, [])
        for session in sessions:
            try:
                await session.close()
            except Exception:
                try:
                    session.close()
                except Exception:
                    logger.warning("browse browser session cleanup failed silently")