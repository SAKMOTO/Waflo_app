"""Waflo Builder job engine.

Isolated, additive async job system. It generates small, self-contained static
projects from a natural-language prompt (or a source URL) using the same LLM
chain as the rest of Waflo, stores them under ``generated_projects/`` and
streams live progress to subscribed clients over WebSockets.

Isolation rules honoured here:
- Generated projects live OUTSIDE the app: ``generated_projects/<id>/{source,
  preview, metadata.json}``. They are never executed inside the Waflo process.
- A Builder failure never affects the rest of the app: every generation runs
  in its own background asyncio task and reports through a job object.
- metadata.json contains NO secrets.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import WebSocket

from builder.providers.crawl_provider import (
    CrawlProviderError,
    default_crawl_provider,
)
from builder.providers.llm_provider import default_llm_provider
from builder.schemas import (
    BuilderEvent,
    BuilderJobStatus,
    BuilderJobView,
    BuilderProjectMeta,
)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GENERATED_ROOT = PROJECT_ROOT / "generated_projects"

# Human-facing phases (also shown as animated steps in the Flutter UI).
STEPS = ["Analyzing", "Planning", "Generating", "Validating", "Ready"]

# Reasonable progress anchors for each status.
STATUS_PROGRESS = {
    "queued": 5,
    "analyzing": 15,
    "planning": 35,
    "generating": 65,
    "validating": 85,
    "preview_ready": 95,
    "completed": 100,
    "failed": 100,
    "cancelled": 100,
}

STATUS_STEP = {
    "analyzing": 0,
    "planning": 1,
    "generating": 2,
    "validating": 3,
    "preview_ready": 4,
    "completed": 4,
    "failed": 3,
    "cancelled": 3,
}

MAX_FILE_BYTES = 200_000

# Larger cap for live preview serving (a generated page may embed images,
# fonts etc. that exceed the text-oriented 200KB code-viewer limit).
PREVIEW_MAX_BYTES = 20_000_000

# Hard cap for a single LLM completion (plan planning or code generation).
# If a provider hangs, the job fails cleanly instead of wedging at "generating".
LLM_COMPLETE_TIMEOUT_SECONDS = float(
    os.environ.get("BUILDER_COMPLETE_TIMEOUT", "300")
)

# ---------------------------------------------------------------------------
# Prompt templates
# ---------------------------------------------------------------------------

PLAN_SYSTEM = (
    "You are the senior product designer and planning engine of Waflo Builder. "
    "You convert an idea (or a brief website analysis) into a precise, "
    "buildable design spec that a front-end engineer can turn into a polished, "
    "premium website. You only return the plan, no code."
)

PLAN_PROMPT = """Create a detailed build plan for the following idea.

Write your plan inside a single block delimited by <plan> and </plan>. Inside,
use exactly these sections (keep each point short and concrete):

- TITLE: a short, catchy project title (max 6 words)
- AUDIENCE: who the site speaks to, in one line
- TONE: the feel of the design in 2-4 adjectives (e.g. "clean, warm, confident")
- PAGES: 2-4 pages/sections and their purpose
- LAYOUT: navigation, header/hero/sections/footer arrangement
- COMPONENTS: the reusable UI pieces needed (cards, buttons, forms, sliders…)
- DESIGN SYSTEM:
  - TYPOGRAPHY: heading style and font stack
  - COLORS: 4-6 exact hex codes (primary, accent, background, text, muted)
  - SPACING: the rhythm between sections
  - CORNER RADIUS and SHADOW style (soft, crisp, none)
- INTERACTIONS: hover states, micro-animations, the mobile menu behaviour
- FUNCTIONALITY: concrete interactions and behaviour
- DATA: where structured data appears (cards, lists, tables, pricing)

Constraints:
- Keep it buildable as ONE polished single-page website with plain HTML + CSS + JavaScript.
- No backend, no database, no external APIs, no paid services.
- Never use or invent API keys, tokens, or credentials.
- The finished site must feel professionally designed, not template-like.

IDEA: {prompt}
"""

CODE_SYSTEM = (
    "You are a senior front-end engineer and design-systems builder. You "
    "hand-write a complete, premium single-page website in vanilla HTML/CSS/JS "
    "from a design spec. No frameworks, no build step, no external dependencies, "
    "no network calls, no secrets — it must look professionally designed when "
    "opened straight from disk. Return ONLY the file blocks."
)

CODE_PROMPT = """Build the website described by this plan.

{plan}

Return each file as a block using this exact format (including the tags):

<file path="index.html">…complete html…</file>
<file path="style.css">…complete css…</file>
<file path="script.js">…complete js…</file>

DESIGN REQUIREMENTS (meet every one):
- Build a real DESIGN SYSTEM: CSS variables in :root for palette, spacing,
  radius, shadows, and a clamp()-based fluid type scale. Use the COLORS hexes.
- Typography with clear hierarchy, generous line-height and section rhythm.
- Layout with CSS Grid + Flexbox, a centered max-width container, sticky header
  with backdrop blur, a strong hero (headline, subline, CTA), alternating
  sections, and a complete footer.
- Visual polish: layered soft shadows, consistent rounded corners, hover &
  focus states, active nav highlight, smooth scrolling, pressed-button effects.
- Motion is TASTEFUL and restrained: CSS transitions, gentle hover lifts, and a
  small script.js for scroll-reveal (IntersectionObserver) and the mobile
  hamburger menu. No autoplay loops, no flashing, nothing distracting.
- Icons: inline SVG only, consistent stroke style (1.5-2px), never emoji.
- Imagery: never external images; use CSS gradients, and inline SVG shapes for
  placeholders. Write real, specific copy — never lorem ipsum.
- Responsive from 320px up; mobile menu collapses the nav.
- Semantic landmarks (header, main, section, footer), visible focus, good contrast.
- Include index.html always; add style.css and script.js as needed.

POLISH CHECKLIST — before finishing, verify ALL of: nav links work, the hero is
strong with a clear headline + call to action, EVERY COMPONENT from the plan is
present, sections flow with consistent spacing, every interaction has hover/focus
feedback, and the footer is complete. No placeholders like "TODO" or "REPLACE",
no truncated "…" inside code, no ellipsis in copy.
"""

POLISH_SYSTEM = (
    "You are a principal design reviewer. You refine an already-working "
    "single-page website toward premium, Lovable-grade quality while keeping it "
    "fully functional. You return the COMPLETE, final files — never snippets, "
    "never ellipsis, never placeholders."
)

POLISH_PROMPT = """Refine this single-page website to a premium, polished standard.

DESIGN SPEC (the ground truth):
{plan}

CURRENT FILES:
{files}

What to improve (how far you take it is limited only by quality):
- Tighten visual hierarchy and the hero's impact (headline, subline, CTA).
- Enforce the design system: consistent palette, spacing rhythm, type scale,
  radius and shadow tokens via CSS variables.
- Add/refine tasteful micro-interactions: hover lifts, button presses, subtle
  scroll-reveal, sticky blurred header, smooth scrolling, mobile hamburger menu.
- Make the layout fully responsive (320px up) and mobile menus solid.
- Strengthen copy: real, specific sentences — no lorem ipsum, no "…".
- Ensure icons are consistent inline SVGs (no emoji) and imagery uses
  gradients/SVG placeholders (no external URLs).
- Accessibility: semantic landmarks, visible focus, adequate contrast.

Return EVERY final file as a block in this exact format (always a full
index.html):

<file path="index.html">…complete html…</file>
<file path="style.css">…complete css…</file>
<file path="script.js">…complete js…</file>

No truncated files, no "TODO"/"REPLACE", no placeholders anywhere. Stay one
self-contained page.
"""

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


@dataclass
class Job:
    job_id: str
    mode: str
    prompt: str
    url: Optional[str] = None
    status: str = BuilderJobStatus.QUEUED.value
    message: str = "Queued…"
    step_index: int = 0
    progress: int = STATUS_PROGRESS["queued"]
    error: Optional[str] = None
    cancelled: bool = False
    plan: str = ""
    project_id: Optional[str] = None
    project: Optional[BuilderProjectMeta] = None
    events: list[BuilderEvent] = field(default_factory=list)
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


_FILE_RE = re.compile(r'<file\s+path=["\']([^"\']+)["\']\s*>([\s\S]*?)</file>')
# Lenient variant for models that drop the closing tag or pad blocks with
# markdown fences: matches up to the next <file tag or end of input, then trims
# any ``` fences so the raw HTML/CSS/JS is recovered.
_LENIENT_FILE_RE = re.compile(
    r'<file\s+path=["\']([^"\']+)["\']\s*>([\s\S]*?)(?=</file>|<file\s+path=|\Z)',
    re.IGNORECASE,
)
_PLAN_RE = re.compile(r"<plan>([\s\S]*?)</plan>", re.IGNORECASE)


def parse_file_blocks(text: str) -> dict[str, str]:
    """Extract ``<file path="...">…</file>`` blocks into a path->content dict."""
    files: dict[str, str] = {}
    if not text:
        return files
    for match in _FILE_RE.finditer(text):
        raw_path = match.group(1).strip()
        content = match.group(2).strip()
        path = _safe_rel_path(raw_path)
        if not path or not content:
            continue
        if path in files:
            # Prefer the longer (more complete) duplicate.
            if len(content) > len(files[path]):
                files[path] = content
            continue
        files[path] = content
    if files:
        return files
    # Fall back to the lenient parser only when the strict one found nothing
    # (e.g. the model dropped a closing tag or wrapped blocks in fences).
    for match in _LENIENT_FILE_RE.finditer(text):
        raw_path = match.group(1).strip()
        content = _strip_fences(match.group(2))
        path = _safe_rel_path(raw_path)
        if not path or not content:
            continue
        if path in files:
            if len(content) > len(files[path]):
                files[path] = content
            continue
        files[path] = content
    return files


def _strip_fences(content: str) -> str:
    out = (content or "").strip()
    if out.startswith("```"):
        out = re.sub(r"^```[A-Za-z0-9\-]*\s*", "", out)
    if out.endswith("```"):
        out = re.sub(r"\s*```$", "", out)
    return out.strip()


def parse_plan(text: str) -> str:
    """Return the plan section of an LLM response (or a trimmed raw answer)."""
    if not text:
        return ""
    match = _PLAN_RE.search(text)
    if match:
        plan = match.group(1).strip()
        return plan if plan else text[:2000]
    # Fall back to a trimmed raw answer for weak models.
    plain = re.sub(r"<(plan|/plan)>", "", text).strip()
    return plain[:4000]


def _safe_rel_path(raw: str) -> str:
    """Normalise and sandbox a relative file path (no traversal, no abs paths)."""
    p = (raw or "").strip().replace("\\", "/")
    p = p.lstrip("/")
    parts = [part for part in p.split("/") if part and part not in (".", "..")]
    if not parts:
        return ""
    return "/".join(parts)[:200]


def _suggest_title(prompt: str, plan: str = "") -> str:
    import re as _re

    plan = plan or ""
    title = ""
    t = _re.search(r"TITLE[:\-]?\s*(.+)?", plan, _re.IGNORECASE)
    if t and t.group(1):
        title = " ".join(t.group(1).split())[:60]
    if not title:
        title = prompt.strip().replace("\n", " ")[:60]
    return title or "Waflo Builder project"


def _files_to_text(files: dict[str, str]) -> str:
    """Serialise the generated files for the polish pass (bounded)."""
    parts: list[str] = []
    for path, content in sorted(files.items()):
        snippet = _bounded(content, 14000)
        parts.append(f"===== {path} =====\n{snippet}\n")
    return "\n".join(parts)[:120000]


def _polish_is_safe_upgrade(polished: str, original: dict[str, str]) -> bool:
    """Only accept the polish pass when it honestly improves on the original."""
    if not polished or "<file" not in polished:
        return False
    candidate = parse_file_blocks(polished)
    if "index.html" not in candidate:
        return False
    original_total = sum(len(v) for v in original.values()) or 1
    candidate_total = sum(len(v) for v in candidate.values())
    # Reject collapsed / truncated / degraded rewrites (e.g. empty style.css).
    if candidate_total < original_total * 0.6 or candidate_total < 1500:
        return False
    for path, content in candidate.items():
        if not content or ">" not in content:
            return False
    return True


class BuilderService:
    def __init__(self) -> None:
        self._jobs: dict[str, Job] = {}
        self._subscribers: dict[str, set[WebSocket]] = {}
        self._llm = default_llm_provider()
        self._crawl = default_crawl_provider()
        GENERATED_ROOT.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self, prompt: str, mode: str = "prompt", url: Optional[str] = None) -> str:
        job_id = time.strftime("%Y%m%d%H%M%S") + "-" + _short_id()
        job = Job(job_id=job_id, mode=mode, prompt=prompt, url=url)
        self._jobs[job_id] = job
        asyncio.create_task(self._run(job_id))
        return job_id

    def get_job(self, job_id: str) -> Optional[BuilderJobView]:
        job = self._jobs.get(job_id)
        if job is None:
            return None
        return self._to_view(job)

    def cancel(self, job_id: str) -> bool:
        job = self._jobs.get(job_id)
        if job is None or job.status in _TERMINAL_STATUSES:
            return False
        job.cancelled = True
        asyncio.create_task(
            self._update(
                job_id,
                BuilderJobStatus.CANCELLED.value,
                "Generation cancelled.",
            )
        )
        return True

    def list_projects(self) -> list[BuilderProjectMeta]:
        metas: list[BuilderProjectMeta] = []
        if not GENERATED_ROOT.exists():
            return metas
        for meta_path in sorted(GENERATED_ROOT.glob("*/metadata.json")):
            try:
                data = json.loads(meta_path.read_text(encoding="utf-8"))
                metas.append(BuilderProjectMeta.model_validate(data))
            except Exception:
                continue
        metas.sort(key=lambda m: m.updated_at, reverse=True)
        return metas

    def get_project(self, project_id: str) -> Optional[BuilderProjectMeta]:
        meta_path = GENERATED_ROOT / _safe_rel_path(project_id) / "metadata.json"
        if not meta_path.exists():
            return None
        try:
            return BuilderProjectMeta.model_validate(
                json.loads(meta_path.read_text(encoding="utf-8"))
            )
        except Exception:
            return None

    def read_project_file(self, project_id: str, rel_path: str) -> Optional[str]:
        proj_dir = (GENERATED_ROOT / _safe_rel_path(project_id)).resolve()
        safe = _safe_rel_path(rel_path)
        if not safe:
            return None
        candidate = (proj_dir / "source" / safe).resolve()
        if not candidate.is_relative_to(proj_dir) or not candidate.is_file():
            return None
        if candidate.stat().st_size > MAX_FILE_BYTES:
            return None
        try:
            return candidate.read_text(encoding="utf-8")
        except Exception:
            return None

    def _resolve_project_file(
        self, project_id: str, rel_path: str, fallback_index: bool = True
    ) -> Optional[Path]:
        """Sandboxed lookup of a generated project file.

        Returns the exact file when it exists; when ``fallback_index`` is set
        and the request targets the site root (no path, a folder, or a missing
        ``.html`` page), falls back to ``index.html`` so the live preview
        behaves like a static site host. ``None`` when nothing can be served.
        """
        proj_dir = (GENERATED_ROOT / _safe_rel_path(project_id)).resolve()
        safe = _safe_rel_path(rel_path)
        if not safe:
            return None
        candidate = (proj_dir / "source" / safe).resolve()
        if candidate.is_relative_to(proj_dir) and candidate.is_file():
            if candidate.stat().st_size <= PREVIEW_MAX_BYTES:
                return candidate

        if fallback_index and (
            safe.lower().endswith(".html") or "." not in safe
        ):
            idx = (proj_dir / "source" / "index.html").resolve()
            if (
                idx.is_relative_to(proj_dir)
                and idx.is_file()
                and idx.stat().st_size <= PREVIEW_MAX_BYTES
            ):
                return idx
        return None

    def read_project_bytes(
        self, project_id: str, rel_path: str, fallback_index: bool = True
    ) -> Optional[bytes]:
        """Binary-safe read used by the live-preview endpoint (images, fonts,
        scripts, plus HTML). Mirrors ``read_project_file`` safety rules."""
        resolved = self._resolve_project_file(project_id, rel_path, fallback_index)
        if resolved is None:
            return None
        try:
            return resolved.read_bytes()
        except Exception:
            return None

    # ------------------------------------------------------------------
    # WebSocket hooks
    # ------------------------------------------------------------------

    def subscribe(self, job_id: str, ws: WebSocket) -> None:
        self._subscribers.setdefault(job_id, set()).add(ws)

    def unsubscribe(self, job_id: Optional[str], ws: WebSocket) -> None:
        if job_id is None:
            return
        subs = self._subscribers.get(job_id)
        if subs:
            subs.discard(ws)
            if not subs:
                self._subscribers.pop(job_id, None)

    async def send_snapshot(self, job_id: str, ws: WebSocket) -> None:
        job = self._jobs.get(job_id)
        if job is None:
            return
        try:
            data = self._to_view(job).model_dump()
            await ws.send_json({"type": "snapshot", **data})
        except Exception:
            pass

    # ------------------------------------------------------------------
    # The generation pipeline
    # ------------------------------------------------------------------

    async def _run(self, job_id: str) -> None:
        job = self._jobs[job_id]
        try:
            await self._update(job_id, "analyzing", "Analysing your idea…")

            context = ""
            if job.mode == "url":
                context = await self._analyse_url(job)

            if job.cancelled:
                return

            await self._update(job_id, "planning", "Turning your idea into a plan…")
            plan_prompt = PLAN_PROMPT.format(prompt=_bounded(job.prompt, 1500) + (f"\n\nWEBSITE ANALYSIS:\n{context}" if context else ""))
            try:
                plan = await asyncio.wait_for(
                    asyncio.to_thread(self._llm.complete, plan_prompt, PLAN_SYSTEM),
                    timeout=LLM_COMPLETE_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                raise RuntimeError(
                    "The planner took too long and was aborted. Please try again."
                )
            job.plan = parse_plan(plan)
            if not job.plan:
                raise RuntimeError("The AI did not return a usable plan.")
            await self._update(job_id, "planning", "Plan ready — writing your project…", progress_hint=45)

            if job.cancelled:
                return

            await self._update(job_id, "generating", "Writing your project code…")
            code_prompt = CODE_PROMPT.format(plan=_bounded(job.plan, 6000))
            try:
                code = await asyncio.wait_for(
                    asyncio.to_thread(self._llm.complete, code_prompt, CODE_SYSTEM),
                    timeout=LLM_COMPLETE_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                raise RuntimeError(
                    "Code generation took too long and was aborted. Please try again."
                )
            files = parse_file_blocks(code)
            if not files:
                raise RuntimeError(
                    "The AI did not return any files in a valid format. "
                    "Please try again."
                )

            if job.cancelled:
                return

            await self._update(job_id, "validating", "Checking your generated files…")
            files = self._finalise_files(files)

            if job.cancelled:
                return

            await self._update(job_id, "validating", "Polishing your design…")
            try:
                polished = await asyncio.wait_for(
                    asyncio.to_thread(
                        self._llm.complete,
                        POLISH_PROMPT.format(
                            plan=_bounded(job.plan, 6000),
                            files=_files_to_text(files),
                        ),
                        POLISH_SYSTEM,
                    ),
                    timeout=LLM_COMPLETE_TIMEOUT_SECONDS,
                )
            except asyncio.TimeoutError:
                polished = ""
            except Exception:
                polished = ""
            if _polish_is_safe_upgrade(polished, files):
                files = self._finalise_files(parse_file_blocks(polished))

            project_id = self._persist(job, files)

            await self._update(
                job_id,
                "completed",
                "Your project is ready!",
                project_id=project_id,
                project=self.get_project(project_id),
            )
        except asyncio.CancelledError:
            pass
        except Exception as e:
            message = str(e) or type(e).__name__
            job.error = message
            await self._update(
                job_id,
                BuilderJobStatus.FAILED.value,
                "Builder couldn't complete this generation: " + message,
                error=message,
            )

    async def _analyse_url(self, job: Job) -> str:
        url = job.url or ""
        if not url.lower().startswith(("http://", "https://")):
            raise RuntimeError(
                "Invalid URL. Use http:// or https:// links."
            )
        if self._crawl is None:
            await self._update(
                job.job_id,
                "analyzing",
                "Firecrawl not configured — building from the URL using model knowledge only. "
                "Set FIRECRAWL_API_KEY in the backend .env for real analysis.",
                progress_hint=10,
            )
            return ""
        try:
            await self._update(job.job_id, "analyzing", f"Analysing {url}…", progress_hint=10)
            content = await self._crawl.scrape(url)
            return (
                f"Only layout, structure, typography, colour, sections and "
                f"components may be reused. Do NOT copy branding, logos, exact "
                f"copy, assets or source code. Produce an independent design.\n\n"
                f"ANALYSED CONTENT:\n{content}"
            )
        except CrawlProviderError as e:
            return (
                f"Could not fetch {url} ({e}). "
                f"Proceed using general knowledge only; do not guess specifics."
            )

    def _finalise_files(self, files: dict[str, str]) -> dict[str, str]:
        """Validate / drop unsafe entries and guarantee an index.html."""
        cleaned: dict[str, str] = {}
        for raw, content in files.items():
            safe = _safe_rel_path(raw)
            if not safe:
                continue
            if len(content.encode()) > MAX_FILE_BYTES:
                continue
            cleaned[safe] = content

        if "index.html" not in cleaned:
            html_links = sorted(p for p in cleaned if p.endswith(".html"))
            links = "\n".join(
                f'<li><a href="{p}">{p}</a></li>' for p in html_links
            ) or "<li>No pages yet</li>"
            cleaned["index.html"] = (
                "<!doctype html><html><head><meta charset='utf-8'>"
                "<title>Waflo Builder project</title></head><body>"
                "<h1>Waflo Builder project</h1><ul>" + links + "</ul></body></html>"
            )
        return cleaned

    def _persist(self, job: Job, files: dict[str, str]) -> str:
        project_id = job.job_id
        proj_dir = GENERATED_ROOT / project_id
        source_dir = proj_dir / "source"
        preview_dir = proj_dir / "preview"
        source_dir.mkdir(parents=True, exist_ok=True)
        preview_dir.mkdir(parents=True, exist_ok=True)

        for rel, content in files.items():
            fp = source_dir
            for part in rel.split("/"):
                fp = fp / part
            fp.parent.mkdir(parents=True, exist_ok=True)
            fp.write_text(content, encoding="utf-8")

        title = _suggest_title(job.prompt, job.plan)
        now = datetime.now(timezone.utc).isoformat()
        meta = BuilderProjectMeta(
            project_id=project_id,
            title=title,
            prompt=job.prompt,
            source_url=job.url,
            created_at=now,
            updated_at=now,
            status=BuilderJobStatus.COMPLETED.value,
            files=sorted(files.keys()),
        )
        (proj_dir / "metadata.json").write_text(
            meta.model_dump_json(indent=2), encoding="utf-8"
        )
        job.project_id = project_id
        job.project = meta
        return project_id

    # ------------------------------------------------------------------
    # Progress events
    # ------------------------------------------------------------------

    async def _update(
        self,
        job_id: str,
        status: str,
        message: str,
        *,
        error: Optional[str] = None,
        project_id: Optional[str] = None,
        project: Optional[BuilderProjectMeta] = None,
        progress_hint: Optional[int] = None,
    ) -> None:
        job = self._jobs.get(job_id)
        if job is None:
            return
        job.status = status
        job.message = message
        job.step_index = STATUS_STEP.get(status, job.step_index)
        job.progress = progress_hint or STATUS_PROGRESS.get(status, job.progress)
        if error is not None:
            job.error = error
        if project_id is not None:
            job.project_id = project_id
        if project is not None:
            job.project = project

        event = BuilderEvent(
            type="progress",
            status=status,
            step_index=job.step_index,
            progress=job.progress,
            message=message,
            time=datetime.now(timezone.utc).isoformat(),
        )
        job.events.append(event)

        await self._broadcast(
            job_id,
            {
                "type": "progress",
                "job_id": job_id,
                "status": status,
                "step_index": job.step_index,
                "progress": job.progress,
                "message": message,
                "project_id": job.project_id,
                "cancelled": job.cancelled,
                "error": error,
            },
        )

    async def _broadcast(self, job_id: str, payload: dict) -> None:
        subs = set(self._subscribers.get(job_id, ()))
        for ws in list(subs):
            try:
                await ws.send_json(payload)
            except Exception:
                self._subscribers.get(job_id, set()).discard(ws)

    def _to_view(self, job: Job) -> BuilderJobView:
        return BuilderJobView(
            job_id=job.job_id,
            status=job.status,
            mode=job.mode,
            prompt=job.prompt,
            url=job.url,
            step_index=job.step_index,
            progress=job.progress,
            message=job.message,
            error=job.error,
            cancelled=job.cancelled,
            project_id=job.project_id,
            events=list(job.events),
            project=job.project,
        )


_TERMINAL_STATUSES = {
    BuilderJobStatus.COMPLETED.value,
    BuilderJobStatus.FAILED.value,
    BuilderJobStatus.CANCELLED.value,
}


def _short_id() -> str:
    import secrets

    return secrets.token_hex(3)


def _bounded(text: str, limit: int) -> str:
    text = (text or "").strip()
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


builder_service = BuilderService()