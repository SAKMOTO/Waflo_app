# ARIA + Firecrawl Integration — Implementation Report

Backend integration of the vendored **Firecrawl Python SDK** into the existing
**ARIA browser agent** (Waflo). No Flutter UI, Rive character, avatar, Razorpay
payment-safety or commerce-agent logic was touched.

---

## 1. What was built

ARIA (the Agent Hub "Researcher" agent) is now a general-purpose web agent. Its
flow is:

```
raw query ──► ARIA BRAIN (plan) ──► [Firecrawl research (facts)] ──► browser-use (live pages) ──► evidence ──► synthesis ──► final answer
```

New backend modules (server/):

| File | Role |
|---|---|
| `vendor_firecrawl.py` | Puts the vendored SDK (`<repo>/firecrawl/apps/python-sdk`, firecrawl-py 4.41.0) first on `sys.path` and drops any shadowing install — exact mirror of `vendor_browser_use.py`. |
| `pydantic_models/aria_models.py` | `UserTask` (immutable `raw_query`), `AriaPlan` (intent/tools/budget/domains), `AriaEvidence`, `AriaSynthesis`. |
| `services/aria_brain.py` | Intent classifier (LLM-first + deterministic fallback), tool router, budgets, domain extraction, source dedup, early-stop rule, final synthesis. |
| `services/firecrawl_service.py` | Async adapter over the vendored SDK: `search_web`, `scrape_url`, `map_links`, `crawl_web`; graceful `FirecrawlError`. |

Modified:

| File | Change |
|---|---|
| `server/services/browser_agent_service.py` | Wired the brain into `start_browser_task`: plan → research → browse → synthesis; new `aria_plan`/`aria_tool`/`aria_evidence`/`aria_synthesis` events; `_build_plan` (20 s bound), `_run_firecrawl_research`; domain extraction now shared + fixed. |
| `server/config.py` | `FIRECRAWL_API_KEY`, `FIRECRAWL_API_URL`. |
| `server/requirements.txt` | Documented the vendored SDK install (no new pip dependency required; the server boots it via `vendor_firecrawl.py`). |
| `.env.example` | Firecrawl placeholders (cloud URL `https://api.firecrawl.dev` or any self-hosted instance). |

## 2. Integration points

- `server/main.py` browse handler → `BrowserAgentService.start_browser_task(query, …)`.
- The brain classifies, then: research phase if plan routes to Firecrawl, then the
  existing browser-use execution (unchanged Agent/BrowserSession/step streaming).
- Final `content` + `done` events are identical, so Flutter is unchanged. New
  `aria_*` events are observability-only; the Flutter parser ignores unknown
  types (`default: break` in `BrowserExecutor._onMessage`).

## 3. Intent decision logic

LLM-first: a compact prompt asks the planner LLM (the same Gemini/Groq browser
LLM) for JSON (`intent`, `focus`, `target_domains`, `tools`, `reason`). Any
parse/validation failure falls back to a deterministic classifier that uses
signal words for **routing, domain detection and validation only** — it never
rewrites the query. Intents: `research`, `shopping`, `comparison`,
`browser_action`, `website_direct`, `price_check`, `general`.

## 4. Tool routing

- `website_direct`, `browser_action` → **browser only** (honour the named site).
- `research`, `shopping`, `price_check`, `comparison` → **hybrid**:
  Firecrawl first for facts, then browser-use with the raw query.
- If the SDK is absent/unconfigured or any call fails → **browser-only** (today's
  behaviour), so ARIA never breaks without Firecrawl.

## 5. Raw-query preservation (query-substitution regression)

`UserTask.raw_query` is immutable; `_build_task_prompt` embeds the user's exact
string; Firecrawl `search_web` receives the exact string. Regression tests assert
the raw query appears verbatim and that no canned phrase ("best wireless
headphones 2026", "mechanical keyboard", etc.) is ever generated. The original
bug string exists **only** in `COMMERCE_INTEGRATION_SUMMARY.md` (a doc example),
not in code.

## 6. Budgets, early stopping, loop prevention

- Per-intent budgets (`firecrawl_search` ≤ 8, `firecrawl_scrape` ≤ 4,
  `browser_steps` ≤ 40); untrusted LLM budgets are clamped (1…200).
- Early stop: research stops once 3 diverse quality sources are captured.
- Browser loop prevention was already active (`loop_detection_enabled=True`,
  `max_steps=50`, `step_timeout=180`, outer `wait_for`), and is retained; the
  browser phase is unchanged.

## 7. Source dedup

`dedupe_sources`: no repeated URLs, max 2 results per domain, favouring
diversity, so one site cannot dominate the evidence.

## 8. Direct domain routing

Domain extraction was fixed to match bare/single-TLD domains (`amazon.in`,
`github.com/waflo`) and full URLs, normalised to host. `website_direct` /
`browser_action` tasks navigate straight to the named domain via
`initial_actions` and allowlist it with the security watchdog, instead of
starting from a search engine.

## 9. Evidence system

Each verified claim becomes `AriaEvidence(source, url, domain, title, content,
kind, quality)`. Evidence from Firecrawl search results and scraped pages is
threaded into the synthesis and into the `aria_evidence` stream for
observability.

## 10. Final synthesis — never "Completed"

`EXECUTION_COMPLETE ▸ SYNTHESIS ▸ FINAL_ANSWER`: browser result + evidence are
combined by `synthesize_answer` into a real, sourced answer (findings + steps +
source URLs). A truthful "could not gather enough information" message is used
only when nothing readable was collected. `tools_used` and `evidence_count` are
reported on `done`.

## 11. Error handling / graceful fallback

- LLM planner failure/timeout (20 s bound) → deterministic fallback.
- Firecrawl unconfigured (no `FIRECRAWL_API_KEY`/`API_URL`) → `[ARIA DECISION] … browser only`;
  the adapter treats "SDK present but not configured" as unavailable, and the SDK
  `api_url` is only passed when set (its `ClientConfig.api_url` is a required
  host string), so no spurious config errors can stall a task.
- Firecrawl unavailable / search error / empty results / scrape errors → logged
  + browser-only; the task still completes.
- Unhandled research errors are caught so the browser phase always runs.

## 12. Security

- API keys live only in backend `Settings` → SDK client; never forwarded to the
  Flutter client, never logged, never in research payloads.
- Razorpay payment safety (approval gates, budget, signature verification,
  audit, safe failure) is **untouched** — only ARIA research code paths changed.
- New `aria_*` events carry only intent/domains/URLs/query — implementation
  details (selectors, reasoning steps) remain filtered.

## 13. Files changed vs untouched

Changed/created (backend only): listed in §1. **Untouched**: `lib/**` (Flutter),
`lib/agents/**`, widget/Rive/Spline assets, `server/services/commerce_agent_service.py`
& Razorpay services, and both vendor trees (`browser-use/`, `firecrawl/`).

## 14. Tests + results

`cd server && python -m pytest tests/ -v` → **53 passed** (19 existing + 34 new in
`tests/test_aria_brain.py`). New coverage: vendored-Firecrawl import & module
imports; intent classification (research/shopping/comparison/direct-site/action/
price/general); raw-query preservation incl. the bug-phrase regression; tool
routing matrix; budget clamping; domain extraction; early stopping; source dedup;
synthesis (answer kept + sources, evidence-only, empty, timeout-flagged); failure
fallbacks (unavailable / search error / empty / partial scrape failure /
browser-only gate); Firecrawl adapter normalisation against a mocked SDK client
(offline, no network, no browser; the browser path is exercised only if you run
a live task manually since it needs Playwright + an LLM key).

## 15. Manual test matrix

- **A** Basic research: "what is machine learning" → plan `research`, hybrid; runs browser.
- **B** Shopping: "best wireless earbuds under ₹5000 ANC" → `shopping`; Firecrawl search + scrapes (if configured), then browser.
- **C** Comparison: "iPhone 16 vs Pixel 9" → `comparison`; wider search budget.
- **D** Direct site: "check amazon.in for iPhone 16 price" → `website_direct`; navigates straight to amazon.in.
- **E** Action on a site: "open github.com/git/git" → `browser_action`; direct nav.
- **F** Price: "what is the price of PS5 in India" → `price_check`.
- **G** Query purity: prompt/answer contain the user's exact sentence; no canned phrases/YEAR substitution.
- **H** Firecrawl off: unset `FIRECRAWL_API_KEY` → server logs `[ARIA DECISION] … browser only`; task completes.
- **I** Firecrawl on: set key + URL → watch `[ARIA FIRECRAWL]` search/scrape + `[ARIA EVIDENCE]`; catalog-style URL `https://api.firecrawl.dev` for cloud.
- **J** Cancellation, timeout and repeated navigation remain as before (flag + tracked task + session cleanup).

## 16. Backward compatibility

- Existing 19 tests pass unmodified; WS event contract (`content`, `done`,
  `error`, `browse_started`, `browse_cancelled`, `agent_step`) unchanged.
- `cd server && python -c "import main"` → startup import OK; `py_compile` clean.
- No lint/typecheck config exists in the repo (no ruff/flake8/pyright), so the
  closest check is the above plus the pytest suite.

## 17. Limitations / next steps

- No Firecrawl key configured in this environment → research phase stays disabled
  unless `FIRECRAWL_API_KEY`/`FIRECRAWL_API_URL` are set (cloud or the vendored
  self-hosted instance via `firecrawl/docker-compose.yaml`).
- Live browser E2E requires Playwright + an LLM key; covered by unit tests offline.
- Structured planner output (`output_format=`) is available for Gemini 3 but the
  planner intentionally uses plain-text JSON for Groq/OpenRouter parity.
- Optional: surface `aria_*` events in the Flutter timeline, add per-domain
  evidence recall, and budget-aware crawl (`crawl_web` already supports it).