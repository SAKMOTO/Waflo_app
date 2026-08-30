<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/FastAPI-0.128-009688?logo=fastapi&logoColor=white" />
  <img src="https://img.shields.io/badge/Razorpay-Test%20Mode-02042B?logo=razorpay&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-green" />
</p>

<h1 align="center">🛍️ Waflo — AI Agentic Commerce</h1>

<p align="center">
  <strong>An AI shopping agent that grows a merchant's revenue and makes them
  transactable by an AI buyer — end to end, on Razorpay test-mode APIs.</strong>
</p>

<p align="center">
  Conversational in-app checkout · Agent-readable catalog · Upsell & cross-sell ·
  Every money action explainable, bounded & gated · Full audit trail
</p>

---

## 📖 Table of Contents

- [🎯 What & Why](#-what--why)
- [✨ The Bar (Safety First)](#-the-bar-safety-first)
- [🖼️ High-Level Architecture](#️-high-level-architecture)
- [🗂️ Repository Structure](#️-repository-structure)
- [🧩 Frontend (Flutter)](#-frontend-flutter)
- [⚙️ Backend (FastAPI + Python)](#️-backend-fastapi--python)
- [💳 The Agentic Checkout Flow](#-the-agentic-checkout-flow)
- [📜 Audit Trail](#-audit-trail)
- [🛠️ Tech Stack](#️-tech-stack)
- [🚀 Getting Started](#-getting-started)
- [🔌 API Reference](#-api-reference)
- [🧪 Testing](#-testing)
- [⚠️ Failure Handling (What Broke)](#️-failure-handling-what-broke)
- [🔐 Security Notes](#-security-notes)
- [🛣️ Roadmap](#️-roadmap)

---

## 🎯 What & Why

**Waflo** is a cross-platform AI-first workspace that ships with a complete
**Agentic Commerce** vertical: an agent that can **grow a merchant's revenue**
(upsell & cross-sell) and **close a full purchase** through an AI buyer, using
**Razorpay's test-mode APIs**.

This targets the **Razorpay AI Buildathon — Track 01: AI Growth & Agentic
Commerce**, the open problem of *agent-to-agent commerce* (NPCI UAP, ACP, AP2,
x402).

It combines three example directions from the brief into one demo:

1. **Conversational in-app checkout** — buy a product through natural language.
2. **Agent-readable catalog** — a deterministic merchant catalog the agent can
   transact against.
3. **Upsell & cross-sell agent** — after a selection, the agent proposes better
   or complementary products to grow basket size.

---

## ✨ The Bar (Safety First)

> **Every money action explainable, bounded and gated.**

This is the heart of the submission and is enforced deliberately in the code:

| Principle | How Waflo enforces it |
|-----------|------------------------|
| **Bounded** | The agent can only `checkout` → `approve` → `confirm`. It is **never** authorized to charge autonomously. A **budget/policy guard** (`commerce_agent_service.py:1134`) blocks any order exceeding the user's stated budget *before* any order or payment exists. |
| **Gated** | A three-step explicit approval gate: `checkout()` creates a pending order (no money moved) → `approve_payment()` builds the Razorpay order only after the user approves (still no charge) → `confirm_payment()` verifies a signature and only then marks it `PAID`. |
| **Explainable** | Every recommendation carries human-readable reasoning; product scoring weight-by-weight; every browser step is streamed; and every action lands in a persistent audit trail. |
| **Audited** | `AuditService` writes a JSON audit file per task. An `GET .../audit` endpoint surfaces it, and failures are recorded with the exact event + status. |

**The audit trail is not an afterthought** — it is a first-class service, and one
documented failure is handled gracefully and recoverably (see
[Failure Handling](#️-failure-handling-what-broke)).

---

## 🖼️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Client (Web/Desktop/Mobile)   │
│   Home Page  ·  Commerce Page (live agent timeline, cards) │
└──────────────────────────┬──────────────────────────────────┘
                           │  WebSocket (/ws/chat) + REST
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Backend (Python)                │
│   main.py (routes)  ·  config.py (settings)                │
├─────────────────────────────────────────────────────────────┤
│  CommerceAgentService         RazorpayService              │
│   • live browser search       • create/verify orders       │
│   • scoring & reasoning       • HMAC signature verify      │
│   • upsell / cross-sell       • test-mode + demo fallback  │
│   • checkout gate             │                            │
├─────────────────────────────────────────────────────────────┤
│  MerchantCatalogService       AuditService                 │
│   • deterministic catalog     • persistent JSON audit trail│
├─────────────────────────────────────────────────────────────┤
│  browser-use (browser agent)  ·  cloud LLM (Gemini/Groq)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Repository Structure

```text
Waflo_app/
├── lib/                          # Flutter client (Dart)
│   ├── main.dart                 # App entry + routes (/, /commerce)
│   ├── pages/
│   │   ├── home_page.dart        # Landing / chat
│   │   ├── chat_page.dart        # Conversational UI
│   │   ├── commerce_page.dart    # AI shopping agent UI
│   │   └── auth/
│   │       └── login_page.dart   # Sign-in / sign-up (Supabase)
│   ├── services/
│   │   ├── chat_web_service.dart # WebSocket + commerce events
│   │   └── razorpay_checkout.dart# Client-side Razorpay checkout
│   ├── theme/colors.dart         # Centralized theme
│   └── widgets/                  # Reusable UI components (see below)
│
├── server/                       # Python backend
│   ├── main.py                   # FastAPI app + all routes
│   ├── config.py                 # Env-driven settings (pydantic)
│   ├── requirements.txt          # Python dependencies
│   ├── pydantic_models/
│   │   ├── chat_body.py          # Chat request models
│   │   └── commerce_models.py    # Full commerce domain models
│   ├── services/
│   │   ├── commerce_agent_service.py  # ⭐ Core agent logic
│   │   ├── razorpay_service.py        # Payment integration
│   │   ├── merchant_catalog_service.py# Agent-readable catalog
│   │   ├── audit_service.py           # Persistent audit trail
│   │   ├── auth_service.py            # JWT + rate limiting
│   │   ├── llm_service.py             # LLM abstraction
│   │   ├── hf_router.py               # Hugging Face router
│   │   ├── search_service.py          # Tavily web search
│   │   └── sort_source_service.py     # Source sorting
│   ├── tests/test_commerce_service_init.py
│   └── test_ws.py                # WebSocket test utility
│
├── assets/report.json            # Bundled demo/report asset
├── .env.example                  # Config template (keys placeholders)
└── README.md
```

> **Note:** The vendored `browser-use/` and `web-ui/` directories and the Python
> `server/venv/` are **gitignored** — install dependencies fresh from
> `server/requirements.txt` instead of committing build artifacts or secrets.

---

## 🧩 Frontend (Flutter)

A cross-platform client (Web, Android, iOS, macOS, Windows, Linux) built with
`Material 3`, Google Fonts, Lottie animations, Markdown rendering, and live
WebSockets.

### Routes (`lib/main.dart`)
| Route | Page | Purpose |
|-------|------|---------|
| `/` | `HomePage` | Landing, search, chat entry |
| `/commerce` | `CommercePage` | The AI shopping agent dashboard |

### Pages
- **`home_page.dart`** — entry landing with navigation to search & commerce.
- **`chat_page.dart`** — conversational interface wired to the backend.
- **`commerce_page.dart`** — the star of the demo: a live timeline of agent
  activity, discovered products, ranked recommendations, and checkout controls.
- **`auth/login_page.dart`** — Supabase-backed sign-in/sign-up.

### Commerce widgets
| Widget | Role |
|--------|------|
| `commerce_agent_timeline.dart` | Streams live agent steps (browse, find, compare) |
| `commerce_product_card.dart` | Product display with match score & reasoning |
| `commerce_controls.dart` | Start / stop agent, input query, checkout actions |

### Services
- **`chat_web_service.dart`** — the WebSocket client; routes commerce events
  (product found, comparison, confirmation, payment) to the UI.
- **`razorpay_checkout.dart`** — runs the Razorpay Checkout SDK after the agent
  builds the order, then reports `payment_id` + signature back to the backend
  for verification.

---

## ⚙️ Backend (FastAPI + Python)

The backend owns the safety-critical commerce logic.

### `server/main.py` — Routes
| Method | Path | Purpose |
|--------|------|---------|
| WS | `/ws/chat` | Real-time chat + commerce events |
| POST | `/chat` | HTTP chat fallback |
| POST | `/api/commerce/agent/start` | Start the shopping agent with a query |
| GET | `/api/commerce/task/{id}` | Get task status |
| POST | `/api/commerce/task/{id}/cancel` | Cancel a running agent |
| GET | `/api/commerce/task/{id}/audit` | Fetch the task's audit trail |
| GET | `/api/commerce/audit/all` | All task audit summaries |
| GET | `/api/products` `/search` `/{id}` | Merchant catalog |
| GET | `/api/commerce/task/{id}/order` | Get the pending order |
| POST | `/api/commerce/task/{id}/checkout` | Build a bounded, gated order |
| POST | `/api/commerce/task/{id}/payments/approve` | User approval → create Razorpay order |
| POST | `/api/commerce/task/{id}/payments/confirm` | Verify payment → mark PAID |
| POST | `/api/webhooks/razorpay` | Razorpay webhook w/ HMAC verification |

### `server/services/commerce_agent_service.py` — ⭐ Core agent
- **Live browser search** via `browser-use` against an allow-listed domain set
  (Google, Amazon.in, Flipkart, Myntra, Croma, Reliance Digital, etc.).
- **Intent analysis** (`_analyze_user_intent`): extracts product type, budget,
  use case, and requirements from free text.
- **Structured extraction + scoring** (`_extract_structured_products`,
  `_score_product`) with human-readable reasoning.
- **Growth actions**: `upsell()` and `cross_sell()` run a *secondary* live
  browser task to propose better/complementary products.
- **Bounded checkout gate**: `checkout()` → `approve_payment()` →
  `confirm_payment()`, with a budget policy guard and payment-failure recovery.

### `server/services/razorpay_service.py` — Payments
- Creates Razorpay orders via the **Orders API** (`POST /v1/orders`).
- Verifies payment integrity with **HMAC-SHA256** signatures (checkout SDK and
  webhook).
- **Demo mode fallback**: if no keys are set, it transparently simulates orders
  and a deterministic success/failure so the entire flow can be demoed
  end-to-end without credentials.

### `server/services/merchant_catalog_service.py` — Agent-readable catalog
A deterministic, locally-stored catalog of merchant products (`Waflo Mechanical
Keyboard Pro`, etc.) that the agent can put through the Razorpay test checkout —
independent of flaky live scraping. This is what makes the merchant
*sellable to an AI buyer end to end*.

### `server/services/audit_service.py` — Audit trail
Persists every event (`event_type`, `action`, `status`, `message`, `metadata`)
to `server/audit_logs/<task_id>.json` with summary statistics.

---

## 💳 The Agentic Checkout Flow

```
User: "buy the Waflo Mechanical Keyboard Pro under ₹5000"
  │
  ▼
① CommerceAgentService.checkout()
   • builds a PENDING order  (NO money moved)
   • budget guard: if ₹ > budget → CheckoutBlockedEvent, returns
  │
  ▼
② approve_payment()  →  user clicks "Approve"
   • creates the Razorpay order (bounded: order created, NOT charged)
   • sends key_id + amount to the client
  │
  ▼
③ Client opens Razorpay Checkout SDK (test mode)
  │
  ▼
④ confirm_payment(payment_id, signature)
   • verifies HMAC signature
   • on success → OrderStatus.PAID, PaymentSuccessEvent
   • on failure → resets to PENDING, admits recovery, lets user retry
```

Each step emits a `PaymentInitiated` / `OrderCreated` / `PaymentSuccess` /
`PaymentFailed` event **and** writes an audit log entry.

---

## 📜 Audit Trail

Every money-related and agent action is recorded. Example flow of audit events:

```
task_start  → intent_analysis → agent_step → product_found
→ checkout_initiated → order_created → payment_success → task_complete
```

Each entry carries `event_type`, `action`, `status`, and a human-readable
`message` with structured `metadata`. Fetch it with:

```bash
curl http://localhost:8000/api/commerce/task/<task_id>/audit
```

---

## 🛠️ Tech Stack

**Frontend (Flutter/Dart)**
- `google_fonts` · `lottie` · `animated_text_kit` · `spline_flutter`
- `web_socket_client` · `flutter_markdown_plus` · `skeletonizer` · `file_picker`

**Backend (Python)**
- `FastAPI` + `uvicorn` + `websockets`
- `browser-use` (browser automation agent)
- `sentence-transformers` (relevance scoring)
- `tavily-python` (web search) · `huggingface-hub` · `openai` · `langchain-google-genai`
- `requests` (Razorpay Orders API) + `hmac` (signature verification)

**Payments**
- Razorpay **Orders API** + **Checkout SDK** in **Test Mode**, with an optional
  demo-mock fallback.

---

## 🚀 Getting Started

### Prerequisites
- Flutter 3.x & Dart 3.x
- Python 3.11+
- (Optional) a public LLM key — Gemini or Groq (fallback to Ollama / Hugging Face)

### 1) Backend
```bash
cd server
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env      # fill in your keys (LLM, Razorpay, etc.)
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 2) Flutter client
```bash
flutter pub get

# terminal 1: backend  →  terminal 2:
flutter run -d chrome
```

> No Razorpay keys? The backend **auto-switches to demo payment mode** so you can
> still run the full checkout demo. Real keys switch it to the live test API.

### 3) Try the agent
1. Open the app → **Shop**.
2. Enter: `"find wireless headphones under ₹3000 with long battery life"`
3. Watch the agent browse, extract, score, and recommend.
4. Select a product → compare → cross-sell → upsell → **Checkout** → **Approve**.
5. Inspect the audit trail at `GET /api/commerce/task/{id}/audit`.

---

## 🔌 API Reference (quick)

```bash
# Start a shopping task
curl -X POST http://localhost:8000/api/commerce/agent/start \
  -H "Content-Type: application/json" \
  -d '{"query":"find wireless headphones under Rs 3000"}'

# Audit trail for a task
curl http://localhost:8000/api/commerce/task/<task_id>/audit

# Build a gated checkout
curl -X POST http://localhost:8000/api/commerce/task/<task_id>/checkout \
  -H "Content-Type: application/json" -d '{"index":0,"quantity":1}'
```

---

## 🧪 Testing

```bash
cd server && python -m pytest tests/ -v     # backend tests
cd .. && flutter analyze                     # frontend static analysis
```

A WebSocket smoke test helper lives at `server/test_ws.py`.

---

## ⚠️ Failure Handling (What Broke)

Part of the brief: **show that failures are handled gracefully.** Three notable
systems do this explicitly:

1. **Browser timeout → partial results.** The live agent is wrapped in a 180s
   timeout (`commerce_agent_service.py:546`). On timeout it does **not** fail the
   whole request — it recovers the products already collected in memory and
   returns them as a "partial result", so the user still gets value.

2. **Payment failure → recoverable retry.** If Razorpay reports `FAILED`,
   `confirm_payment()` resets the order to `PENDING`, clears the stale order id,
   and explicitly tells the user they can re-approve and retry
   (`commerce_agent_service.py:1346`).

3. **Budget-policy enforcement.** If a checkout would exceed the user's stated
   budget, a `CheckoutBlockedEvent` is emitted and **no order/payment is created**
   (`commerce_agent_service.py:1134`) — a graceful "no" instead of an over-limit
   charge.

These are the exact "what broke, and how you got out" stories featured in the
demo video.

---

## 🔐 Security Notes

- **Secrets are never committed.** `.env`, `server/.env`, and `web-ui/.env` are
  gitignored. Use `.env.example` as the template.
- **Key handling on the client:** only the Razorpay `key_id` (publishable) is
  sent to the client; the `key_secret` stays server-side.
- **Webhook integrity:** `X-Razorpay-Signature` is verified with HMAC before any
  webhook-triggered state change.
- **Agent autonomy is capped:** the agent can discover, recommend, upsell, and
  cross-sell freely, but **charging always requires explicit user approval**.

---

## 🛣️ Roadmap

- [ ] User auth + rate limiting wired end-to-end (scaffold in `auth_service.py`)
- [ ] Deploy backend to the cloud (Browser Use Cloud recommended)
- [ ] Persistent user profiles & purchase history
- [ ] A/B testing on recommendation scoring
- [ ] Add more merchant categories to the agent-readable catalog

---

## 📄 License

MIT — see [`LICENSE`](./LICENSE).

---

<p align="center">
  Built for the <strong>Razorpay AI Buildathon · Track 01: AI Growth & Agentic Commerce</strong>
</p>
