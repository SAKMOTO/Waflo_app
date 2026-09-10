# ✨ Waflo Builder — Integration Report

**Status:** Milestone 1 vertical slice live end-to-end (Flutter UI → FastAPI job → LLM plan/code → project files → live progress).

Date: 2026-09-05

---

## What was built

The Waflo Builder generates small, self-contained static websites from a prompt
(or an analysed source URL) on the existing FastAPI backend, mirrored after the
core generation concept of the vendored `open-lovable` repo (LLM emits
`<file path="...">…</file>` blocks), but **isolated**:

- It is a separate backend module with its own job engine. A Builder failure
  never touches chat, commerce, or the ARIA/browser agents.
- Generated code is **never executed inside Waflo** — projects are written to
  `server/generated_projects/<id>/{source, preview, metadata.json}` only.
- It reuses Waflo's existing API keys/config; nothing is forwarded to the
  Flutter client.

### Backend (new, additive)

| File | Purpose |
|---|---|
| `server/builder/__init__.py` | package marker |
| `server/builder/schemas.py` | Pydantic request/response + job status enum |
| `server/builder/providers/llm_provider.py` | LLM provider abstraction (reuses Waflo chain) |
| `server/builder/providers/llm_claude.py` | optional Anthropic provider (`BUILDER_LLM_PROVIDER=anthropic`) |
| `server/builder/providers/crawl_provider.py` | URL analysis via existing Firecrawl adapter |
| `server/builder/service.py` | async job engine, file parsing, cancellation, storage |
| `server/builder/router.py` | REST router + `/ws/builder` WebSocket |
| `server/main.py` | registers the two builder routers (2 lines) |
| `server/tests/test_builder_service.py` | 10 tests (parsing, validation, pipeline, cancel, secrets) |

### Frontend (new / additive)

| File | Purpose |
|---|---|
| `lib/pages/builder_page.dart` | Builder UI: idle / running-progress / done / error states, in-app code viewer |
| `lib/services/builder_web_service.dart` | HTTP client + WebSocket live-progress stream |
| `lib/widgets/side_bar.dart` | new "Builder" nav entry (index 3) |
| `lib/pages/{home,chat,commerce}_page.dart` | wired `onNavigateBuilder` |
| `lib/main.dart` | route `/builder` added |
| `pubspec.yaml` | added `http: ^1.2.0` |

### Endpoints

```
GET  /api/builder/health                      → {"status":"ok"}
POST /api/builder/generate                    {prompt, url?, mode:"prompt"|"url"} → {job_id}
GET  /api/builder/jobs/{job_id}               → full job snapshot (status, progress, events, project)
POST /api/builder/jobs/{job_id}/cancel        → {cancelled}
GET  /api/builder/projects                    → completed project metadata list
GET  /api/builder/projects/{project_id}       → project metadata
GET  /api/builder/projects/{project_id}/file?path=index.html → {content}
WS   /ws/builder                              subscribe {"action":"subscribe","job_id":...}
                                              → snapshot + progress events until terminal
```

### Job states & progress anchors

`queued → analyzing(15) → planning(35) → generating(65) → validating(85) → completed(100)`,
with `failed` / `cancelled` handled in every UI state.

---

## WORKING NOW ✅

- **Full pipeline**: prompt → structured plan (TITLE/PAGES/LAYOUT/…) → code files
  → `generated_projects/<id>/` persisted → done. Verified live with OpenRouter/Gemini.
- **Live progress**: WebSocket push + polling safety net; verified (snapshot replay
  mid-run works).
- **Cancel**: verified mid-generation (progress stops, no partial project saved).
- **Error handling**: no-files / unconfigured provider / dead backend all fail
  gracefully with a friendly message + Try Again. Never crashes the app.
- **Flutter**: `flutter analyze` 0 errors, `flutter build web --release` succeeds.
- **Backend tests**: 10/10 passing.
- Existing chat/commerce/products endpoints still return 200 (nothing broken).
- **Local health**: backend `:8000` + Electron `:57127` running now.

## REQUIRES CONFIGURATION 🔧

- **LLM (default)**: Builder uses the **cloud chain** — local Ollama (if
  running), then `GEMINI_API_KEY`, then `HF_TOKEN`, then `OPENROUTER_API_KEY`.
  (Ollama is skipped by default via `BUILDER_SKIP_OLLAMA=true`; completions
  ~12k tokens peg the laptop CPU/GPU. Opt in with `BUILDER_SKIP_OLLAMA=false`.)
  **2026 note:** OpenRouter's `:free` model slugs were retired and now 404, so
  OpenRouter is only a last-resort fallback with a paid slug
  (`minimax/minimax-m3` or `OPENROUTER_MODEL`). Provide at least a
  `GEMINI_API_KEY` (or `HF_TOKEN`) for generation to succeed.
- **URL mode**: real website analysis needs **`FIRECRAWL_API_KEY`** (reuses the
  existing vendored Firecrawl adapter). Without it, URL mode still works but
  builds from model knowledge only (with a note in the progress messages).
- **Anthropic (optional)**: `BUILDER_LLM_PROVIDER=anthropic` + `ANTHROPIC_API_KEY`.
- **Backend reachability**: the Flutter client points at `http://127.0.0.1:8000`
  (same convention as the existing chat WebSocket). Start the backend first.

## FUTURE IMPROVEMENTS 🚀

- **Sandbox preview**: actually render `generated_projects/<id>/source/index.html`
  (e.g. local static server / iframe sandbox, then Vercel or E2B like open-lovable)
  and wire the "Open Preview" button. Milestone 2.
- **Multi-file polish**: React/Vite-style app trees with package install + dev-server
  diagnostics (port open-lovable's `apply-ai-code` + `monitor-vite-logs` ideas).
- **Edit loop**: conversational follow-ups against an existing project
  (open-lovable's `analyze-edit-intent` / edit-diff flow).
- **Pick a provider per mode** via `BUILDER_LLM_PROVIDER` already scaffolded.
- **Supabase project listing** instead of local metadata (interface is already
  isolated in `BuilderService`).
- Derived files (e.g. favicon) and a downloadable `.zip` of the project.

## Files generated during testing (kept as examples)

```
server/generated_projects/20260905210727-680f33/  → "Roasty Brews Landing" (index.html + style.css)
server/generated_projects/…/                      → a couple more smoke-test projects
```