"""ARIA brain schemas (backend).

The ARIA brain treats the user's words as an immutable ``UserTask`` and derives
an executable ``AriaPlan`` from it. The **raw query is never rewritten** — it
travels verbatim through planning, Firecrawl research, browser execution and
final synthesis. Every claim the agent produces becomes an ``AriaEvidence``
entry so the final answer can be traced back to a source.
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

# Valid intent labels produced by the ARIA brain classifier.
AriaIntent = Literal[
    "research",
    "shopping",
    "comparison",
    "browser_action",
    "website_direct",
    "price_check",
    "general",
]

# The two tools ARIA can invoke.
AriaTool = Literal["firecrawl", "browser"]

INTENT_NAMES: tuple[AriaIntent, ...] = (
    "research",
    "shopping",
    "comparison",
    "browser_action",
    "website_direct",
    "price_check",
    "general",
)


class UserTask(BaseModel):
    """The user's request as a task. ``raw_query`` is immutable by construction."""

    model_config = ConfigDict(frozen=True)

    raw_query: str = Field(..., description="Original user query, never rewritten.")
    task_id: str = ""
    normalized_goal: str = ""


class AriaPlan(BaseModel):
    """An executable plan derived from a user task."""

    intent: AriaIntent
    tools: list[AriaTool] = Field(
        default_factory=list,
        description="Ordered tool list ARIA will try, in priority order.",
    )
    reason: Optional[str] = None
    focus: Optional[str] = Field(
        default=None,
        description="Short human phrase describing what the answer should focus on.",
    )
    target_domains: list[str] = Field(
        default_factory=list,
        description="Domains explicitly named in the user's task.",
    )
    budget: dict[str, int] = Field(
        default_factory=dict,
        description="Per-tool resource budget, e.g. firecrawl_search / firecrawl_scrape / browser_steps.",
    )


class AriaEvidence(BaseModel):
    """One traceable source of information used to build the final answer."""

    source: AriaTool
    url: str
    domain: str
    title: Optional[str] = None
    content: Optional[str] = None
    step: Optional[str] = None
    kind: str = "page"  # page | search | curated
    quality: str = "medium"  # high | medium | low (safety/accuracy heuristic)


class AriaSynthesis(BaseModel):
    """The final assembled answer plus its provenance."""

    summary: str
    evidence: list[AriaEvidence] = Field(default_factory=list)
    sources: list[str] = Field(default_factory=list)
    tools_used: list[AriaTool] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)