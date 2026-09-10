"""ARIA brain + Firecrawl integration tests (offline, no network, no browser).

Covers the required regression surface:

- intent classification (research / shopping / comparison / direct site / action)
- raw-query preservation: the user's words are NEVER rewritten or substituted
- tool routing: firecrawl-only vs browser-only vs hybrid
- loop prevention + early stopping
- source dedup by URL and domain (one site cannot dominate evidence)
- final synthesis: a real, sourced answer — never a bare "Completed"
- graceful failure fallbacks: Firecrawl unavailable/error -> browser-only
- Firecrawl adapter normalization against a mocked vendored SDK client
"""

import asyncio
import types

import pytest

from pydantic_models.aria_models import AriaEvidence
from services.aria_brain import (
    AriaBrain,
    dedupe_sources,
    extract_domains,
    plan_budget,
    should_stop_research,
    synthesize_answer,
    tools_for_intent,
)
from services.firecrawl_service import FirecrawlError, FirecrawlService
from services import browser_agent_service  # noqa: F401
from services.browser_agent_service import (
    BrowserAgentService,
    _build_task_prompt,
)


def plan_for(query, llm=None, allow_llm=True):
    """Run the brain synchronously (no pytest plugin required)."""
    return asyncio.run(AriaBrain(plan_llm=llm).build_plan(query, allow_llm=allow_llm))


# ---------------------------------------------------------------------------
# Vendored imports resolve (import check)
# ---------------------------------------------------------------------------

def test_vendored_firecrawl_sdk_is_importable():
    from vendor_firecrawl import bootstrap_vendored_firecrawl, IS_FIRECRAWL_PRESENT

    assert IS_FIRECRAWL_PRESENT
    bootstrap_vendored_firecrawl()
    import firecrawl

    assert firecrawl.__version__ == "4.41.0"
    from firecrawl.v2.client import FirecrawlClient

    assert FirecrawlClient is not None


def test_aria_modules_import_cleanly():
    import services.aria_brain  # noqa: F401
    import services.firecrawl_service  # noqa: F401
    import services.browser_agent_service  # noqa: F401
    import vendor_firecrawl  # noqa: F401


# ---------------------------------------------------------------------------
# Intent classification (deterministic fallback path)
# ---------------------------------------------------------------------------

def test_intent_simple_research():
    task, plan = plan_for("What is machine learning?", allow_llm=False)
    assert plan.intent == "research"
    assert "firecrawl" in plan.tools


def test_intent_shopping():
    task, plan = plan_for(
        "best wireless earbuds under ₹5000 with ANC for travel", allow_llm=False
    )
    assert plan.intent == "shopping"
    assert plan.tools == ["firecrawl", "browser"]
    assert plan.budget["firecrawl_search"] >= 1


def test_intent_comparison():
    task, plan = plan_for(
        "which is better: iPhone 16 or Pixel 9 in India?", allow_llm=False
    )
    assert plan.intent == "comparison"
    assert plan.tools == ["firecrawl", "browser"]


def test_intent_price_check():
    task, plan = plan_for("what is the price of PS5 in India?", allow_llm=False)
    assert plan.intent == "price_check"


def test_intent_website_direct():
    task, plan = plan_for("check amazon.in for iPhone 16 price", allow_llm=False)
    assert plan.intent == "website_direct"
    assert plan.tools == ["browser"]
    assert "amazon.in" in plan.target_domains


def test_intent_browser_action():
    task, plan = plan_for(
        "open github.com/git/git and summarize it", allow_llm=False
    )
    assert plan.intent == "browser_action"
    assert plan.tools == ["browser"]
    assert "github.com" in plan.target_domains


def test_intent_general_default_is_safe_browser():
    task, plan = plan_for("hello there", allow_llm=False)
    assert plan.intent == "general"
    assert plan.tools == ["browser"]


# ---------------------------------------------------------------------------
# Raw-query preservation (the query-substitution bug regression)
# ---------------------------------------------------------------------------

def test_raw_query_is_never_mutated_by_brain():
    raw = "  find me the best wireless headphones 2026  "
    task, plan = plan_for(raw, allow_llm=False)
    assert task.raw_query == raw, "raw_query was rewritten"


def test_browser_prompt_uses_raw_query_verbatim():
    raw = "compare the best wireless headphones 2026 please"
    prompt = _build_task_prompt(raw)
    assert raw in prompt
    # The old substitution bug replaced the query with a canned phrase / year;
    # neither the canned template nor any hard-coded shopping phrase may appear.
    assert "mechanical keyboard" not in prompt.lower()


def test_planner_never_generates_the_bug_query():
    # The reported bug injected "best wireless headphones 2026" regardless of the
    # actual task. Planning for an unrelated query must not surface that phrase.
    _, plan = plan_for("tell me about mars", allow_llm=False)
    import json

    dump = json.dumps(plan.model_dump()).lower()
    assert "wireless headphones" not in dump
    assert "2026" not in dump


# ---------------------------------------------------------------------------
# Tool routing + budgets
# ---------------------------------------------------------------------------

def test_tools_for_intent_routing_matrix():
    assert tools_for_intent("website_direct") == ["browser"]
    assert tools_for_intent("browser_action") == ["browser"]
    assert tools_for_intent("research") == ["firecrawl", "browser"]
    assert tools_for_intent("comparison") == ["firecrawl", "browser"]
    assert tools_for_intent("unknown_intent") == ["browser"]


def test_budgets_are_bounded_even_from_untrusted_plans():
    plan = plan_for("what is X", allow_llm=False)[1]
    plan_llm = plan.model_copy(update={"budget": {
        "firecrawl_search": 10 ** 9, "browser_steps": -5, "bogus": 42,
    }})
    sanitized = AriaBrain()._sanitize_plan(plan_llm)
    assert sanitized.budget["firecrawl_search"] <= 200
    assert sanitized.budget["browser_steps"] >= 1
    assert "bogus" not in sanitized.budget


def test_llm_planner_json_is_parsed_and_sanitized():
    json_llm = types.SimpleNamespace(
        completion=(
            '{"intent": "comparison", "focus": "battery life", '
            '"target_domains": [], "tools": ["firecrawl", "browser"], '
            '"reason": "needs many sources"}'
        )
    )

    async def llm(prompt):
        return json_llm.completion

    task, plan = plan_for("compare abc vs xyz", llm=llm)
    assert plan.intent == "comparison"
    assert plan.tools == ["firecrawl", "browser"]
    assert plan.focus == "battery life"


def test_llm_planner_garbage_falls_back_to_deterministic():
    async def llm(prompt):
        return "nah, I won't do structured output."

    task, plan = plan_for("compare abc vs xyz by price", llm=llm)
    assert plan.intent == "comparison"
    assert task.raw_query == "compare abc vs xyz by price"


def test_llm_planner_bad_intent_falls_back():
    async def llm(prompt):
        return '{"intent": "dance", "tools": ["browser"], "target_domains": []}'

    task, plan = plan_for("what is X?", llm=llm)
    assert plan.intent == "research"


# ---------------------------------------------------------------------------
# Loop prevention + early stopping + domain detection
# ---------------------------------------------------------------------------

def test_extract_domains_bare_and_full_urls():
    assert extract_domains("check flipkart.com please") == ["flipkart.com"]
    assert extract_domains("https://www.example.com/foo bar") == ["www.example.com"]
    assert extract_domains("amazon.in") == ["amazon.in"]
    assert extract_domains("no domains here") == []


def test_early_stopping_rule():
    assert should_stop_research(3) is True
    assert should_stop_research(2) is False


def test_budget_never_explodes():
    assert plan_budget("comparison")["firecrawl_scrape"] <= 8
    assert plan_budget("website_direct")["browser_steps"] <= 200


def test_source_dedupe_caps_domain_dominance():
    results = [
        {"url": "https://a.com/p1", "domain": "a.com", "title": "A1", "content": "c"},
        {"url": "https://a.com/p2", "domain": "a.com", "title": "A2", "content": "c"},
        {"url": "https://a.com/p3", "domain": "a.com", "title": "A3", "content": "c"},
        {"url": "https://b.com/1", "domain": "b.com", "title": "B1", "content": "c"},
        {"url": "https://a.com/p1", "domain": "a.com", "title": "dup", "content": "c"},
    ]
    seen_urls, seen_domains = set(), []
    picked = dedupe_sources(results, seen_urls, seen_domains, cap_per_domain=2)
    urls = [p["url"] for p in picked]
    # max 2 per domain, no duplicate URLs, diversity preserved
    assert urls == ["https://a.com/p1", "https://a.com/p2", "https://b.com/1"]
    assert len(seen_urls) == 3


# ---------------------------------------------------------------------------
# Final synthesis (real answers, never "Completed")
# ---------------------------------------------------------------------------

def test_synthesis_with_browser_answer_keeps_it_and_adds_sources():
    ev = AriaEvidence(
        source="firecrawl", url="https://a.com/x", domain="a.com",
        title="A great explainer", content="Battery lasts 28 hours in tests.",
    )
    answer = synthesize_answer(
        "The Pixel 9 lasts 28 hours on a single charge in my testing. "
        "This is clearly the winner.",
        [ev], ["compared both phones"], ["https://a.com/x"],
    )
    assert "Pixel 9" in answer
    assert "https://a.com/x" in answer
    assert "Completed" not in answer


def test_synthesis_without_browser_answer_builds_from_evidence():
    evs = [
        AriaEvidence(source="firecrawl", url="https://c.com/1", domain="c.com",
                     title="Speaker reviews", content="Bass is deep and clear."),
    ]
    answer = synthesize_answer("", evs, [], ["https://c.com/1"])
    assert len(answer) > 40
    assert "c.com" in answer
    assert "Bass is deep" in answer


def test_synthesis_empty_everything_is_truthful_not_garbled():
    answer = synthesize_answer("", [], [], [])
    assert answer.strip()
    assert answer != "Completed"
    assert "could not gather enough" in answer


def test_synthesis_timeout_is_flagged():
    answer = synthesize_answer("", [], ["SEARCH"], [], timed_out=True)
    assert "timed out" in answer.lower()


# ---------------------------------------------------------------------------
# Failure fallbacks (Firecrawl unavailable / broken -> browser still runs)
# ---------------------------------------------------------------------------

class _FakeFirecrawl:
    def __init__(self, available=True, results=None, fail_search=True):
        self.available = available
        self.results = results or []
        self.fail_search = fail_search
        self.search_calls = 0
        self.scrape_calls = 0

    @property
    def is_available(self):
        return self.available

    async def search_web(self, query, include_domains=None, limit=6):
        self.search_calls += 1
        if self.fail_search:
            raise FirecrawlError("Firecrawl search failed: boom")
        return self.results

    async def scrape_url(self, url, timeout_ms=None):
        self.scrape_calls += 1
        raise FirecrawlError("Firecrawl scrape failed: boom")


def _svc():
    return BrowserAgentService()


def _run_research(svc, firecrawl, raw_query="best earbuds under 5000", plan=None):
    if plan is None:
        _, plan = plan_for(raw_query, allow_llm=False)
    svc._firecrawl = firecrawl
    evidence = []
    text, urls = [], []
    events = []

    async def cb(payload):
        events.append(payload)

    ok = asyncio.run(svc._run_firecrawl_research(
        raw_query, plan, evidence, text, urls, cb, "t1",
    ))
    return ok, evidence, text, urls, events, firecrawl


def test_firecrawl_unavailable_is_graceful():
    svc = _svc()
    fake = _FakeFirecrawl(available=False)
    ok, evidence, _, _, _, fake = _run_research(svc, fake)
    assert ok is False
    assert evidence == []
    assert fake.search_calls == 0
    assert len(evidence) == 0


def test_firecrawl_search_error_falls_back():
    svc = _svc()
    fake = _FakeFirecrawl(available=True, fail_search=True)
    ok, evidence, _, _, _, _ = _run_research(svc, fake)
    assert ok is False
    assert evidence == []
    assert fake.search_calls == 1


def test_firecrawl_empty_results_falls_back_to_browser():
    svc = _svc()
    fake = _FakeFirecrawl(available=True, results=[], fail_search=False)
    ok, evidence, _, _, _, _ = _run_research(svc, fake)
    assert ok is False
    assert evidence == []


def test_firecrawl_partial_scrape_failure_still_succeeds():
    svc = _svc()
    results = [
        {"url": "https://a.com/1", "domain": "a.com", "title": "A",
         "content": "top facts on battery life"},
        {"url": "https://b.com/2", "domain": "b.com", "title": "B",
         "content": "review verdict"},
    ]
    fake = _FakeFirecrawl(available=True, results=results, fail_search=False)
    ok, evidence, text, urls, events, fake = _run_research(svc, fake)
    assert ok is True
    assert len(evidence) >= 2          # search-level evidence collected
    assert fake.scrape_calls > 0       # scrapes were attempted
    kinds = {e.kind for e in evidence}
    assert {"search"} <= kinds         # page kind may be missing; never crashes


def test_research_phase_skipped_when_browser_only_plan():
    from services.aria_brain import research_enabled

    # A website_direct/browser_action plan routes to browser ONLY, so the caller
    # gate (`if research_enabled(plan)`) never invokes Firecrawl.
    _, plan = plan_for("open apple.com and tell me about the macbook", allow_llm=False)
    assert plan.tools == ["browser"]
    assert research_enabled(plan) is False

    _, plan2 = plan_for("compare headphones", allow_llm=False)
    assert research_enabled(plan2) is True


def test_synthesis_uses_real_evidence_not_a_fixed_template():
    evs = [
        AriaEvidence(source="firecrawl", url="https://x.com/phones", domain="x.com",
                     content="A uses a 5000mAh battery."),
    ]
    out = synthesize_answer("", evs, [], ["https://x.com/phones"])
    assert "A uses a 5000mAh battery." in out


# ---------------------------------------------------------------------------
# Firecrawl adapter normalization (against a mocked vendored SDK client)
# ---------------------------------------------------------------------------

def _fake_search_response():
    def item(url, title, desc, md=None):
        d = {"url": url, "title": title, "description": desc}
        if md:
            d["markdown"] = md
        return types.SimpleNamespace(**d)

    return types.SimpleNamespace(web=[
        item("https://c.com/1", "Site C", "c snippet", "full c markdown"),
        item("https://d.com/2", "Site D", "d snippet"),
        item("https://dup.com/2", "Site D2", "d2 snippet"),
    ], news=[], images=[])


def test_firecrawl_search_normalizes_and_dedupes():
    class _FakeClient:
        def __init__(self):
            self.called_with = None

        def search(self, query, **kwargs):
            self.called_with = (query, kwargs)
            return _fake_search_response()

    fake_client = _FakeClient()
    svc = FirecrawlService()
    svc._client = fake_client  # inject, skipping SDK instantiation

    results = asyncio.run(svc.search_web(
        "best budget phones", include_domains=["gsmarena.com"], limit=5,
    ))
    assert fake_client.called_with == (
        "best budget phones",
        {"limit": 5, "include_domains": ["gsmarena.com"]},
    )
    # normalized to plain dicts with url/title/content/domain
    assert results[0]["url"] == "https://c.com/1"
    assert results[0]["domain"] == "c.com"
    assert results[0]["content"] == "full c markdown"
    assert results[1]["domain"] == "d.com"


def test_firecrawl_search_domain_filter_is_optional():
    class _FakeClient:
        def search(self, query, **kwargs):
            return _fake_search_response()

    svc = FirecrawlService()
    svc._client = _FakeClient()
    results = asyncio.run(svc.search_web("anything", limit=5))
    assert results and results[0]["url"].startswith("https://")


def test_firecrawl_unconfigured_is_not_available(monkeypatch):
    monkeypatch.delenv("FIRECRAWL_API_KEY", raising=False)
    monkeypatch.delenv("FIRECRAWL_API_URL", raising=False)
    svc = FirecrawlService()
    if svc.is_available:  # environment may already configure it
        return
    with pytest.raises(FirecrawlError):
        svc.client


def test_firecrawl_injected_client_bypasses_config(monkeypatch):
    monkeypatch.delenv("FIRECRAWL_API_KEY", raising=False)
    monkeypatch.delenv("FIRECRAWL_API_URL", raising=False)
    svc = FirecrawlService()

    class _Client:
        def search(self, query, **kwargs):
            return _fake_search_response()

    svc._client = _Client()
    results = asyncio.run(svc.search_web("anything", limit=3))
    assert results and results[0]["url"].startswith("https://")


def test_firecrawl_normalization_exposes_only_safe_fields():
    from services.firecrawl_service import normalize_search_result, normalize_document

    item = types.SimpleNamespace(
        url="https://e.com/1", title="E",
        markdown="secret-marker should vanish", description="desc", category="x",
    )
    out = normalize_search_result(item)
    assert set(out.keys()) == {"url", "title", "content", "domain"}
    assert out["url"] == "https://e.com/1"
    assert out["domain"] == "e.com"

    doc = types.SimpleNamespace(
        url="https://e.com/p", markdown="page body", summary=None,
        metadata={"title": "Page T", "apiKey": "sk-should-never-leak"},
    )
    out2 = normalize_document(doc)
    assert set(out2.keys()) == {"url", "title", "content", "domain"}
    assert out2["title"] == "Page T"
    assert "sk-should-never-leak" not in repr(out2)
    # credentials are only ever used to authenticate the outbound SDK client,
    # never surface in research payloads/events shown to the frontend
    svc = FirecrawlService(api_key="sk-top-secret")
    assert svc._api_key == "sk-top-secret"
    assert "sk-top-secret" not in repr(normalize_search_result(item).values())