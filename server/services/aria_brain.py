"""ARIA brain — intent planner, tool router, budgets and answer synthesis.

ARIA's brain decides HOW a user's raw query should be executed:

1. It always keeps the user's query verbatim (``UserTask.raw_query`` is
   immutable; no template substitution is ever applied).
2. It classifies the intent (LLM-first, deterministic fallback) and picks the
   tool(s): Firecrawl (fast web research), browser-use (real browsing/actions)
   or both (hybrid: research first, then drive the browser with the raw query).
3. It budgets each phase so a runaway loop is impossible.
4. Evidence is deduplicated by URL and domain so the answer is not dominated by
   one site.
5. ``synthesize_answer`` turns the browser output + collected evidence into a
   real, sourced answer — never a bare "Completed".

The deterministic classifier uses simple signal words for *routing, domain
detection and validation only* — it never rewrites the user's query.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Optional, Sequence, Callable, Awaitable

from pydantic_models.aria_models import (
    AriaEvidence,
    AriaPlan,
    AriaTool,
    INTENT_NAMES,
    UserTask,
)

logger = logging.getLogger(__name__)

PlanLLM = Callable[[str], Awaitable[str]]

_DOMAIN_TOKEN = r"[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?"
_URL_RE = re.compile(
    r"(?<![\w.@])(?:https?://)?"
    r"(?:" + _DOMAIN_TOKEN + r"\.)+[a-zA-Z]{2,}"
    r"(?::\\d+)?"
    r"(?:/[^\s<>\"']*)?"
    r"(?![\w.@])",
    re.IGNORECASE,
)

_COMPARISON_PATTERN = re.compile(
    r'\b(vs|versus)\b|\b(?:compare|comparison|difference between)\b'
    r'|\bwhich is better\b|\bbetter(?: than)?\b|\bor\b',
    re.IGNORECASE,
)
_PRICE_PATTERN = re.compile(
    r'\b(price|cost|how much|inr|rupees?)\b|\b[₹$]\s*\d|\bunder\s*[₹$]\s*\d',
    re.IGNORECASE,
)
_SHOP_PATTERN = re.compile(
    r'\b(buy|order|purchase|shop|deal(s)?|discount|delivery|cart)\b'
    r'|\bbest\b|\bcheap(er|est)?\b|\bbudget\b',
    re.IGNORECASE,
)
_RESEARCH_PATTERN = re.compile(
    r'\b(what is|what are|how does|how do|explain|why|history|about)\b'
    r'|\b(research|summar|review|guide|learn|tutorial|news|latest)\b',
    re.IGNORECASE,
)
_ACTION_PATTERN = re.compile(
    r'\b(open|visit|go to|navigate|enter|sign ?in|log ?in|login|register|submit|'
    r'fill|click|download|upload|search for me)\b',
    re.IGNORECASE,
)

INTENT_BUDGETS: dict[str, dict[str, int]] = {
    "website_direct": {"browser_steps": 40},
    "browser_action": {"browser_steps": 40},
    "price_check": {"firecrawl_search": 6, "firecrawl_scrape": 2, "browser_steps": 20},
    "shopping": {"firecrawl_search": 6, "firecrawl_scrape": 3, "browser_steps": 25},
    "comparison": {"firecrawl_search": 8, "firecrawl_scrape": 4, "browser_steps": 20},
    "research": {"firecrawl_search": 6, "firecrawl_scrape": 2, "browser_steps": 25},
    "general": {"browser_steps": 30},
}

# Priority order in which the deterministic classifier tries rules.
DIRECT_TOOLS: dict[str, list[AriaTool]] = {
    "website_direct": ["browser"],
    "browser_action": ["browser"],
    "price_check": ["firecrawl", "browser"],
    "shopping": ["firecrawl", "browser"],
    "comparison": ["firecrawl", "browser"],
    "research": ["firecrawl", "browser"],
    "general": ["browser"],
}


# ---------------------------------------------------------------------------
# Domain detection (routing aid — never replaces the query)
# ---------------------------------------------------------------------------

def extract_domains(query: str) -> list[str]:
    """Return normalized host-only strings for domain-like tokens in a query.

    Matches bare domains (flipkart.com, amazon.in), full URLs and paths, then
    reduces each to its host with ``www.`` retained.
    """
    domains: list[str] = []
    for m in _URL_RE.findall(query or ""):
        d = m.lower().rstrip(".,;:!?“”\"'")
        if d.startswith(("http://", "https://")):
            d = d.split("//", 1)[1].split("/")[0]
        else:
            d = d.split("/", 1)[0]
            d = d.split(":", 1)[0]
        if "." not in d or len(d) <= 3:
            continue
        if not re.search(r"[a-z]", d):
            continue
        if d not in domains:
            domains.append(d)
    return domains


def plan_budget(intent: str) -> dict[str, int]:
    return dict(INTENT_BUDGETS.get(intent, INTENT_BUDGETS["general"]))


def tools_for_intent(intent: str) -> list[AriaTool]:
    return list(DIRECT_TOOLS.get(intent, DIRECT_TOOLS["general"]))


def research_enabled(plan: AriaPlan) -> bool:
    """True when the plan routes to Firecrawl (i.e. a research phase should run)."""
    return "firecrawl" in plan.tools


# ---------------------------------------------------------------------------
# Evidence deduplication / early stopping
# ---------------------------------------------------------------------------

def dedupe_sources(
    results: Sequence[dict],
    seen_urls: set[str],
    seen_domains: list[str],
    cap_per_domain: int = 2,
) -> list[dict]:
    """Pick diverse new sources from raw search results.

    Skips URLs already recorded and caps how many results from the same domain
    are admitted, so one site cannot dominate the evidence. ``seen_urls`` and
    ``seen_domains`` (a list for counting) are updated in place.
    """
    picked: list[dict] = []
    for result in results:
        url = (result.get("url") or "").strip()
        domain = (result.get("domain") or "").strip().lower()
        if not url or url in seen_urls or not domain:
            continue
        if seen_domains.count(domain) >= cap_per_domain:
            continue
        seen_urls.add(url)
        seen_domains.append(domain)
        picked.append(result)
    return picked


def should_stop_research(evidence_count: int) -> bool:
    """Early-stop rule: 3 diverse quality sources are enough to move to action/synthesis."""
    return evidence_count >= 3


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

def _snippet(text: Optional[str], length: int = 160) -> str:
    if not text:
        return ""
    flat = re.sub(r"\s+", " ", text).strip()
    if len(flat) <= length:
        return flat
    return flat[:length].rstrip() + "…"


def _source_line(ev: AriaEvidence) -> str:
    label = ev.title or ev.domain or ev.url
    return f"- {label} — {ev.url}"


def synthesize_answer(
    browser_answer: str,
    evidence: Sequence[AriaEvidence],
    collected_steps: Sequence[str],
    collected_urls: Sequence[str],
    timed_out: bool = False,
) -> str:
    """Combine browser output + Firecrawl evidence into a real, sourced answer.

    Guarantees: never returns a bare "Completed"/empty string; if there is any
    evidence at all, it is surfaced so the user sees the actual facts.
    """
    seen_urls: list[str] = []
    for ev in evidence:
        if ev.url and ev.url not in seen_urls:
            seen_urls.append(ev.url)
    for u in collected_urls:
        if u and u not in seen_urls:
            seen_urls.append(u)

    browser_answer = (browser_answer or "").strip()
    strong_answer = len(browser_answer) >= 40

    findings = [ev for ev in evidence if (ev.content or "").strip()]
    findings = findings[:6]

    parts: list[str] = []

    if strong_answer:
        parts.append(browser_answer)
    elif findings:
        narrative = []
        for ev in findings:
            snippet = _snippet(ev.content)
            if snippet:
                narrative.append(f"- {_snippet(ev.title or ev.domain, 80)}: {snippet}")
        if narrative:
            parts.append(
                "I gathered the following from the web research:\n" + "\n".join(narrative)
            )
        if collected_steps:
            parts.append(
                "I verified this by browsing the live pages.\n"
                + "\n".join(f"• {s}" for s in collected_steps[:6])
            )
    elif collected_steps:
        parts.append(
            "What I did:\n" + "\n".join(f"• {s}" for s in collected_steps[:10])
        )
        if timed_out:
            parts.append("Note: the research run timed out before a full answer was assembled.")

    if seen_urls:
        parts.append("**Sources:**\n" + "\n".join(f"- {u}" for u in seen_urls[:10]))

    if not parts:
        parts.append(
            "I could not gather enough readable information to answer this request"
            + (" (the research run timed out)." if timed_out else ".")
            + " Please try rephrasing or giving a more specific detail."
        )

    return "\n\n".join(parts).strip()


# ---------------------------------------------------------------------------
# Brain
# ---------------------------------------------------------------------------

class AriaBrain:
    """Classifies the user's task and produces an executable plan."""

    def __init__(self, plan_llm: Optional[PlanLLM] = None) -> None:
        self.plan_llm = plan_llm

    # -- public API ---------------------------------------------------------

    async def build_plan(self, raw_query: str, allow_llm: bool = True) -> tuple[UserTask, AriaPlan]:
        """Turn a raw query into an immutable task + plan. Query never rewritten."""
        task = UserTask(raw_query=raw_query)
        plan = None
        if allow_llm and self.plan_llm is not None:
            try:
                plan = await self._llm_plan(raw_query)
            except Exception as exc:  # graceful fallback on any planner failure
                logger.warning(f"[ARIA DECISION] LLM planner failed, using fallback: {exc}")
        if plan is None:
            plan = self._fallback_plan(raw_query)
        plan = self._sanitize_plan(plan)
        logger.info("[ARIA QUERY] raw_query=%r", task.raw_query)
        logger.info(
            "[ARIA INTENT] intent=%s focus=%s domains=%s",
            plan.intent, plan.focus, plan.target_domains,
        )
        logger.info(
            "[ARIA PLAN] tools=%s budget=%s reason=%s",
            plan.tools, plan.budget, plan.reason,
        )
        return task, plan

    # -- deterministic fallback classifier ----------------------------------

    def _fallback_plan(self, query: str) -> AriaPlan:
        q = (query or "").strip()
        domains = extract_domains(q)
        lower = q.lower()

        intent: str = "general"
        reason: Optional[str] = None
        target_domains = [d for d in domains if not d.startswith("www.")]
        if not target_domains:
            target_domains = [d.lstrip("www.") for d in domains]

        if domains:
            # A site is mentioned: honour it with the browser unless the query
            # clearly asks for an open-ended comparison/research across the web.
            if _ACTION_PATTERN.search(lower) or len(domains) == 1:
                if _ACTION_PATTERN.search(lower):
                    intent, reason = "browser_action", "explicit action on a named site"
                else:
                    intent, reason = "website_direct", "a specific site was named"
        elif _COMPARISON_PATTERN.search(lower):
            intent, reason = "comparison", "comparison wording detected"
        elif _PRICE_PATTERN.search(lower):
            if _SHOP_PATTERN.search(lower):
                intent, reason = "shopping", "price + shopping intent"
            else:
                intent, reason = "price_check", "pricing question"
        elif _SHOP_PATTERN.search(lower):
            intent, reason = "shopping", "shopping intent detected"
        elif _RESEARCH_PATTERN.search(lower):
            intent, reason = "research", "informational/research wording"
        elif _ACTION_PATTERN.search(lower):
            intent, reason = "browser_action", "action wording detected"

        return AriaPlan(
            intent=intent,  # type: ignore[arg-type]
            tools=tools_for_intent(intent),
            reason=reason,
            target_domains=target_domains,
            budget=plan_budget(intent),
        )

    # -- LLM planner --------------------------------------------------------

    async def _llm_plan(self, raw_query: str) -> Optional[AriaPlan]:
        assert self.plan_llm is not None
        prompt = (
            "You are ARIA's planner. Classify the USER TASK below into a compact "
            "machine-readable plan. Return ONLY one JSON object, no prose, with keys:\n"
            '- "intent": one of "research","shopping","comparison","browser_action",'
            '"website_direct","price_check","general"\n'
            '- "focus": short phrase (<=10 words) describing what the answer must cover\n'
            '- "target_domains": list of explicit website domains mentioned (none if absent)\n'
            '- "tools": list from {"firecrawl","browser"}: pick "firecrawl" to gather facts '
            'from the web first, "browser" to browse/act on a live page; use both for '
            'research + action, use only "browser" for one specific site\n'
            '- "reason": one short phrase justifying the tool choice\n\n'
            f"USER TASK: {raw_query}\n"
        )
        text = await self.plan_llm(prompt)
        try:
            payload = self._extract_json(text)
            plan = self._plan_from_payload(payload, raw_query)
            return plan
        except Exception as exc:  # malformed LLM output -> deterministic fallback
            logger.warning(f"[ARIA DECISION] planner JSON invalid ({exc}); falling back")
            return None

    @staticmethod
    def _extract_json(text: str) -> dict:
        if not text:
            raise ValueError("empty planner response")
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```[a-zA-Z]*\s*", "", cleaned)
            cleaned = re.sub(r"\s*```$", "", cleaned)
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start == -1 or end <= start:
            raise ValueError("no JSON object found")
        parsed = json.loads(cleaned[start : end + 1])
        if not isinstance(parsed, dict):
            raise ValueError("JSON payload is not an object")
        return parsed

    def _plan_from_payload(self, payload: dict, raw_query: str) -> AriaPlan:
        intent = str(payload.get("intent") or "general").strip().lower()
        if intent not in INTENT_NAMES:
            raise ValueError(f"unknown intent {intent!r}")

        tool_values = payload.get("tools")
        tools: list[AriaTool] = []
        if isinstance(tool_values, list):
            for t in tool_values:
                t = str(t).strip().lower()
                if t in ("firecrawl", "browser") and t not in tools:
                    tools.append(t)  # type: ignore[arg-type]
        if not tools:
            tools = tools_for_intent(intent)

        domains = payload.get("target_domains") or []
        if not isinstance(domains, list):
            domains = []
        domains = [str(d).strip().lstrip("www.") for d in domains if str(d).strip()]
        if not domains:
            domains = [d.lstrip("www.") for d in extract_domains(raw_query)]

        return AriaPlan(
            intent=intent,  # type: ignore[arg-type]
            tools=tools,
            reason=str(payload.get("reason") or "")[:200] or None,
            focus=str(payload.get("focus") or "").strip()[:80] or None,
            target_domains=domains[:5],
            budget=plan_budget(intent),
        )

    def _sanitize_plan(self, plan: AriaPlan) -> AriaPlan:
        """Clamp budgets/sizes regardless of source (LLM or fallback)."""
        keys = {"browser_steps", "firecrawl_search", "firecrawl_scrape"}
        budget = {k: max(1, min(int(v or 1), 200)) for k, v in plan.budget.items() if k in keys}
        budget = {**plan_budget(plan.intent), **budget}
        return plan.model_copy(
            update={
                "budget": budget,
                "target_domains": [d for d in plan.target_domains if d][:6],
                "tools": plan.tools or tools_for_intent(plan.intent),
            }
        )