from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import traceback
import asyncio
import logging
from typing import Optional
from uuid import uuid4

from pydantic_models.chat_body import ChatBody
from pydantic_models.commerce_models import (
    CommerceAgentRequest,
    MerchantProduct,
    OrderStatus,
)
from services.llm_service import LLMService
from services.sort_source_service import SortSourceService
from services.search_service import SearchService
from services.commerce_agent_service import CommerceAgentService, BROWSER_USE_AVAILABLE
from services.browser_agent_service import BrowserAgentService
from builder.router import router as builder_router
from builder.router import socket_router as builder_socket_router


app = FastAPI()

# CORS: the Flutter/Electron client is served from a browser origin
# (http://127.0.0.1:57127) and calls the backend over HTTP (the Builder
# feature, /api/... REST endpoints). Without CORS headers the browser
# renderer blocks those fetches with "Failed to fetch". The backend only
# binds 127.0.0.1, so allowing all origins here is local-only and safe
# (no remote site can reach it).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=False,
)

# Waflo Builder (isolated project generation) — additive, no impact on the
# existing chat / commerce / browse handlers.
app.include_router(builder_router)
app.include_router(builder_socket_router)

search_service = SearchService()
sort_source_service = SortSourceService()
llm_service = LLMService()
commerce_agent_service = CommerceAgentService()
browser_agent_service = BrowserAgentService()


# Chat WebSocket
@app.websocket("/ws/chat")
async def websocket_chat_endpoint(websocket: WebSocket):

    print("1. WebSocket endpoint called")

    await websocket.accept()

    print("2. WebSocket accepted")

    try:

        while True:

            print("3. Waiting for JSON")

            # Receive JSON from Flutter
            data = await websocket.receive_json()

            print("4. Received:", data)

            query = data.get("query")
            file_name = data.get("file_name")
            file_base64 = data.get("file_base64")
            request_type = data.get("type", "chat")  # 'chat' or 'commerce'

            print("5. Query:", query, "File:", file_name, "Type:", request_type)

            # Handle commerce requests using our integrated CommerceAgentService
            if request_type == "commerce":
                # Run commerce request as an asyncio task so it doesn't block the websocket loop
                # (allowing the user to send cancellation events)
                asyncio.create_task(handle_commerce_request(websocket, data))
                continue

            # Agent Hub browser-research requests (ARIA) using the vendored browser-use
            if request_type == "browse":
                asyncio.create_task(handle_browse_request(websocket, data))
                continue

            # Original chat functionality
            if not query and not file_base64:

                await websocket.send_json({
                    "type": "error",
                    "data": "Query and file are missing"
                })

                continue

            # Writing agent (Sunny): pure LLM drafting, NO web search. The model
            # streams a finished piece straight back through `content`/`done`.
            if request_type == "writing":
                await websocket.send_json({
                    "type": "content",
                    "data": "\n"
                })
                for chunk in llm_service.generate_response(query, []):
                    if chunk:
                        await websocket.send_json({
                            "type": "content",
                            "data": chunk
                        })
                await websocket.send_json({"type": "done"})
                continue

            # Search web (only if query exists).
            # NOTE: web_search does slow network full-text fetches; run it off
            # the event loop so WebSocket pings are still answered.
            if query:
                search_results = await asyncio.to_thread(search_service.web_search, query)
            else:
                search_results = []

            print("6. Search completed")

            # Sort sources
            sorted_results = sort_source_service.sort_sources(
                query,
                search_results.get("results", []) if type(search_results) == dict else search_results
            ) if query else []

            print("7. Sources sorted")

            # Send search results (now containing both 'results' and 'images' arrays)
            await websocket.send_json({
                "type": "search_result",
                "data": sorted_results if type(sorted_results) == list else sorted_results.get("results", [])
            })

            # Send web images to flutter
            if type(search_results) == dict and "images" in search_results:
                await websocket.send_json({
                    "type": "web_images",
                    "data": search_results["images"]
                })

            # HF Multi-Modal Routing
            from services.hf_router import HFRouter
            hf_router = HFRouter()

            if query and hf_router.is_image_request(query):
                # Send typing indicator
                await websocket.send_json({
                    "type": "content",
                    "data": "\n\n*Generating image...*\n\n"
                })
                # Call Text-to-Image model
                b64_img = hf_router.generate_image(query)
                if b64_img:
                    await websocket.send_json({
                        "type": "generated_image",
                        "data": b64_img
                    })
                else:
                    await websocket.send_json({
                        "type": "content",
                        "data": "Failed to generate image."
                    })
            else:
                # Normal Text Generation
                for chunk in llm_service.generate_response(
                    query,
                    sorted_results if type(sorted_results) == list else sorted_results.get("results", []),
                    file_name,
                    file_base64
                ):
                    if chunk:
                        print("8. Sending chunk:", chunk[:50])
                        await websocket.send_json({
                            "type": "content",
                            "data": chunk
                        })

            # Tell Flutter response is finished
            await websocket.send_json({
                "type": "done"
            })

            print("9. Response completed")

    except WebSocketDisconnect as e:

        print(f"Client disconnected: {e.code}")

    except Exception as e:

        print("Unexpected error occurred")

        traceback.print_exc()

        try:

            await websocket.send_json({
                "type": "error",
                "data": str(e)
            })

        except Exception:

            pass

    finally:

        print("10. WebSocket handler finished")


async def handle_commerce_request(websocket: WebSocket, data: dict):
    """Handle commerce/shopping requests using browser-use agent"""
    try:
        query = data.get("query")
        action = data.get("action", "start")  # 'start', 'cancel'
        task_id = data.get("task_id")

        print(f"Commerce request - Action: {action}, Query: {query}, Task ID: {task_id}")

        if action == "cancel" and task_id:
            # Cancel existing task
            success = await commerce_agent_service.cancel_task(
                task_id, 
                lambda event: asyncio.create_task(websocket.send_json(event))
            )
            await websocket.send_json({
                "type": "commerce_cancelled",
                "task_id": task_id,
                "success": success
            })
            return

        # Follow-up / growth actions always target an existing task_id
        if task_id:
            event_cb = lambda event: asyncio.create_task(websocket.send_json(event))

            if action == "select":
                index = int(data.get("index", -1))
                await commerce_agent_service.select_product(task_id, index, event_cb)
                return

            if action == "confirm":
                await commerce_agent_service.confirm_selection(task_id, event_cb)
                return

            if action == "compare":
                raw = data.get("indexes") or []
                indexes = [int(i) for i in raw] if isinstance(raw, list) else []
                await commerce_agent_service.compare_products(task_id, indexes, event_cb)
                return

            if action == "cross_sell":
                index = int(data.get("index", 0))
                await commerce_agent_service.cross_sell(task_id, index, event_cb)
                return

            if action == "upsell":
                index = int(data.get("index", 0))
                await commerce_agent_service.upsell(task_id, index, event_cb)
                return

            # Phase 4 — Merchant checkout with Razorpay test payment
            if action == "checkout":
                index = int(data.get("index", 0))
                quantity = int(data.get("quantity", 1) or 1)
                await commerce_agent_service.checkout(task_id, index, quantity, event_cb)
                return

            if action == "approve":
                await commerce_agent_service.approve_payment(task_id, event_cb)
                return

            if action == "confirm_payment":
                payment_id = data.get("payment_id") or data.get("razorpay_payment_id")
                signature = data.get("signature") or data.get("razorpay_signature")
                await commerce_agent_service.confirm_payment(
                    task_id, payment_id, signature, event_cb
                )
                return

            if action == "cancel_checkout":
                await commerce_agent_service.cancel_checkout(task_id, event_cb)
                return

        if action == "start" and query:
            # Start new commerce agent task
            async def send_event(event_data: dict):
                try:
                    await websocket.send_json(event_data)
                except Exception as e:
                    print(f"Failed to send commerce event: {e}")

            # Create commerce request
            commerce_request = CommerceAgentRequest(
                query=query,
                max_budget=float(data.get("max_budget")) if data.get("max_budget") else None,
                use_case=data.get("use_case"),
                requirements=data.get("requirements", "").split(",") if isinstance(data.get("requirements"), str) and data.get("requirements") else []
            )

            # Pre-check availability so we only announce a task that can actually run.
            if not BROWSER_USE_AVAILABLE:
                await send_event({
                    "type": "error", "task_id": "error",
                    "message": "browser-use is not installed", "error_type": "ImportError"
                })
                return
            if not commerce_agent_service.llm:
                await send_event({
                    "type": "error", "task_id": "error",
                    "message": "No LLM provider configured (set GEMINI_API_KEY or GROQ_API_KEY)",
                    "error_type": "ConfigurationError"
                })
                return

            # Generate the task_id NOW and announce it immediately so the client can
            # cancel during the long browser run. The browser execution happens in a
            # tracked background asyncio.Task so the WebSocket loop stays responsive.
            task_id = str(uuid4())
            commerce_agent_service.active_tasks[task_id] = True
            commerce_agent_service.background_tasks[task_id] = None

            await websocket.send_json({
                "type": "commerce_started",
                "task_id": task_id
            })

            def _background_done(bg_task):
                # Always surface background exceptions instead of silently swallowing them.
                try:
                    bg_task.result()
                except asyncio.CancelledError:
                    print(f"[commerce] task {task_id} cancelled")
                except Exception as e:
                    print(f"[commerce] background task {task_id} raised: {e}")
                    traceback.print_exc()
                    asyncio.create_task(send_event({
                        "type": "error", "task_id": task_id,
                        "message": f"Agent error: {str(e)}", "error_type": type(e).__name__
                    }))
                finally:
                    commerce_agent_service.active_tasks[task_id] = False
                    commerce_agent_service.background_tasks.pop(task_id, None)

            bg = asyncio.create_task(
                commerce_agent_service.start_commerce_agent(commerce_request, send_event, task_id=task_id)
            )
            commerce_agent_service.background_tasks[task_id] = bg
            bg.add_done_callback(_background_done)
        else:
            await websocket.send_json({
                "type": "error",
                "data": "Invalid commerce request"
            })

    except Exception as e:
        print(f"Commerce request error: {e}")
        traceback.print_exc()
        await websocket.send_json({
            "type": "error",
            "data": f"Commerce error: {str(e)}"
        })


async def handle_browse_request(websocket: WebSocket, data: dict):
    """Handle Agent Hub web-research (ARIA) requests using the vendored browser-use.

    Mirrors the commerce handler: the task-id is generated HERE and announced
    immediately (``browse_started``) so the client can cancel during the long
    browser run, then the actual browser execution happens in a tracked
    background asyncio.Task.
    """
    try:
        query = data.get("query")
        action = data.get("action", "start")  # 'start', 'cancel'
        task_id = data.get("task_id")

        print(f"Browse request - Action: {action}, Query: {query}, Task ID: {task_id}")

        async def send_event(event_data: dict):
            try:
                await websocket.send_json(event_data)
            except Exception as e:
                print(f"[ARIA WS] failed to send event to client {task_id}: {e}")

        if action == "cancel" and task_id:
            success = await browser_agent_service.cancel_task(task_id, send_event)
            await websocket.send_json({
                "type": "browse_cancelled",
                "task_id": task_id,
                "success": success,
            })
            return

        if not (action == "start" and query):
            await websocket.send_json({
                "type": "error",
                "data": "Invalid browse request (need action:'start' and a query)"
            })
            return

        print(f"[ARIA WS] browse start accepted: query={query!r} -> spawning background task")

        if not browser_agent_service.is_ready:
            await send_event({
                "type": "error", "task_id": "error",
                "message": "No LLM provider configured for the browser agent (set GEMINI_API_KEY or GROQ_API_KEY)",
                "error_type": "ConfigurationError"
            })
            return

        task_id = str(uuid4())
        browser_agent_service.active_tasks[task_id] = True
        browser_agent_service.background_tasks[task_id] = None

        await websocket.send_json({
            "type": "browse_started",
            "task_id": task_id
        })

        def _background_done(bg_task):
            try:
                bg_task.result()
            except asyncio.CancelledError:
                print(f"[ARIA WS] browse task {task_id} cancelled")
            except Exception as e:
                print(f"[ARIA WS] browse task {task_id} raised: {e}")
                traceback.print_exc()
                asyncio.create_task(send_event({
                    "type": "error", "task_id": task_id,
                    "message": f"Browser agent error: {str(e)}", "error_type": type(e).__name__
                }))
            finally:
                browser_agent_service.active_tasks[task_id] = False
                browser_agent_service.background_tasks.pop(task_id, None)

        bg = asyncio.create_task(
            browser_agent_service.start_browser_task(query, send_event, task_id=task_id)
        )
        browser_agent_service.background_tasks[task_id] = bg
        bg.add_done_callback(_background_done)

    except Exception as e:
        print(f"Browse request error: {e}")
        traceback.print_exc()
        await websocket.send_json({
            "type": "error",
            "data": f"Browse error: {str(e)}"
        })


# Normal HTTP chat endpoint
@app.post("/chat")
def chat_endpoint(body: ChatBody):

    search_results = search_service.web_search(
        body.query
    )

    sorted_results = sort_source_service.sort_sources(
        body.query,
        search_results.get("results", []) if type(search_results) == dict else search_results
    )

    response = ""

    for chunk in llm_service.generate_response(
        body.query,
        sorted_results
    ):

        response += chunk

    return {
        "response": response
    }


# Commerce Agent HTTP Endpoints
@app.post("/api/commerce/agent/start")
async def start_commerce_agent_http(request: CommerceAgentRequest):
    """Start a commerce agent via HTTP (returns task_id for WebSocket monitoring)"""
    # For HTTP, we can't provide real-time events, so we'll run it synchronously
    # and return the final result
    try:
        async def dummy_event_callback(event_data: dict):
            pass  # Ignore events for HTTP endpoint
        
        task_id = await commerce_agent_service.start_commerce_agent(
            request,
            dummy_event_callback
        )
        
        return {
            "task_id": task_id,
            "status": "started",
            "message": "Commerce agent started. Use WebSocket for real-time updates."
        }
    except Exception as e:
        return {
            "error": str(e),
            "status": "failed"
        }


@app.get("/api/commerce/task/{task_id}")
def get_task_status(task_id: str):
    """Get status of a commerce task"""
    is_running = commerce_agent_service.active_tasks.get(task_id, False)
    logs = commerce_agent_service.get_audit_logs(task_id)
    
    return {
        "task_id": task_id,
        "is_running": is_running,
        "audit_logs": [log.model_dump() for log in logs]
    }


@app.post("/api/commerce/task/{task_id}/cancel")
async def cancel_task_http(task_id: str):
    """Cancel a commerce task via HTTP"""
    success = await commerce_agent_service.cancel_task(task_id)
    return {
        "task_id": task_id,
        "cancelled": success
    }


@app.get("/api/commerce/task/{task_id}/audit")
def get_task_audit(task_id: str):
    """Get audit trail for a specific task"""
    logs = commerce_agent_service.get_audit_logs(task_id)
    summary = commerce_agent_service.audit_service.get_audit_summary(task_id)
    return {
        "task_id": task_id,
        "audit_logs": [log.model_dump() for log in logs],
        "total_entries": len(logs),
        "summary": summary
    }


@app.get("/api/commerce/audit/all")
def get_all_audit_summaries():
    """Get audit summaries for all tasks"""
    task_ids = commerce_agent_service.audit_service.get_all_task_ids()
    summaries = []
    for task_id in task_ids:
        summary = commerce_agent_service.audit_service.get_audit_summary(task_id)
        summaries.append(summary)
    return {
        "total_tasks": len(task_ids),
        "summaries": summaries
    }


# ---------------------------------------------------------------------------
# Phase 4 — Waflo merchant catalog, orders and Razorpay test checkout (REST)
# ---------------------------------------------------------------------------


@app.get("/api/products")
def list_products(category: Optional[str] = None) -> dict:
    """List the Waflo merchant catalog (deterministic local data)."""
    products = commerce_agent_service.merchant_catalog.list_products()
    if category:
        products = [p for p in products if p.category == category]
    return {"products": [p.model_dump() for p in products], "count": len(products)}


@app.get("/api/products/search")
def search_products(q: str = "", category: Optional[str] = None) -> dict:
    """Search the merchant catalog by keyword / category."""
    products = commerce_agent_service.merchant_catalog.search(q, category)
    return {"products": [p.model_dump() for p in products], "count": len(products)}


@app.get("/api/products/{product_id}")
def get_product(product_id: str) -> dict:
    product = commerce_agent_service.merchant_catalog.get_product(product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")
    return product.model_dump()


@app.get("/api/commerce/task/{task_id}/order")
def get_task_order(task_id: str) -> dict:
    """Return the stored order (if any) for a commerce task."""
    order = commerce_agent_service.get_order(task_id)
    if order is None:
        raise HTTPException(status_code=404, detail="No order for this task")
    return order.model_dump()


@app.post("/api/commerce/task/{task_id}/checkout")
async def checkout_task_http(task_id: str, index: int = 0, quantity: int = 1) -> dict:
    """Create a (gated) checkout preview for a recommended product. No money moves."""

    async def noop(event_data: dict):
        pass

    ok = await commerce_agent_service.checkout(task_id, index, quantity, noop)
    if not ok:
        raise HTTPException(status_code=400, detail="Checkout could not be initiated")
    order = commerce_agent_service.get_order(task_id)
    return {"checkout_ready": True, "order": order.model_dump() if order else None}


@app.post("/api/commerce/task/{task_id}/payments/approve")
async def approve_payment_http(task_id: str) -> dict:
    """Approve the gated checkout and create the Razorpay (test) order. Still no charge."""

    async def noop(event_data: dict):
        pass

    ok = await commerce_agent_service.approve_payment(task_id, noop)
    if not ok:
        raise HTTPException(status_code=400, detail="Payment approval failed")
    order = commerce_agent_service.get_order(task_id)
    return {
        "approved": True,
        "order": order.model_dump() if order else None,
        "razorpay_order_id": order.razorpay_order_id if order else None,
        "key_id": commerce_agent_service.razorpay.key_id
        if commerce_agent_service.razorpay.configured
        else None,
        "test_mode": commerce_agent_service.razorpay.test_mode,
    }


@app.post("/api/commerce/task/{task_id}/payments/confirm")
async def confirm_payment_http(
    task_id: str,
    payment_id: str,
    signature: Optional[str] = None,
) -> dict:
    """Confirm the result of a completed payment (demo or verified live payment)."""

    async def noop(event_data: dict):
        pass

    ok = await commerce_agent_service.confirm_payment(task_id, payment_id, signature, noop)
    order = commerce_agent_service.get_order(task_id)
    return {
        "paid": ok,
        "order": order.model_dump() if order else None,
    }


@app.post("/api/webhooks/razorpay")
async def razorpay_webhook(request: Request) -> dict:
    """Razorpay webhook. Verifies the X-Razorpay-Signature before trusting anything.

    Only the bounded payment events are handled; other events are acknowledged.
    """
    raw_body = await request.body()
    headers = request.headers
    signature = headers.get("x-razorpay-signature")

    razorpay = commerce_agent_service.razorpay

    if not razorpay.webhook_secret or not signature:
        # Without a configured secret we refuse to process the webhook as a security
        # measure (bounded money action). Log it and return 400.
        logger = logging.getLogger("webhooks")
        logger.warning("[razorpay] webhook received but secret/signature missing; ignoring")
        raise HTTPException(status_code=400, detail="Missing webhook signature")

    if not razorpay.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    try:
        import json
        data = json.loads(raw_body.decode("utf-8"))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid webhook payload")

    event_type = data.get("event", "")
    payload = data.get("payload", {}) or {}
    payment = (payload.get("payment", {}) or {}).get("entity", {}) or {}
    order = (payload.get("order", {}) or {}).get("entity", {}) or {}

    payment_id = payment.get("id")
    order_id = order.get("id")

    # We only act on payment.captured / payment.failed via the resolved status.
    succeeded = event_type == "payment.captured"
    status = OrderStatus.PAID if succeeded else OrderStatus.FAILED

    # Find the matching Waflo order by razorpay_order_id if possible.
    target_task = None
    for tid, state in commerce_agent_service.task_data.items():
        stored = state.get("pending_order")
        if stored and stored.razorpay_order_id == order_id:
            target_task = tid
            break

    if target_task and payment_id:
        stored = commerce_agent_service.task_data[target_task].get("pending_order")
        if stored:
            stored.status = status
            if succeeded:
                stored.razorpay_payment_id = payment_id
            commerce_agent_service._store_order(target_task, stored)
            commerce_agent_service._add_audit_log(
                target_task,
                "payment_webhook",
                "razorpay_webhook",
                "completed" if succeeded else "error",
                f"Webhook {event_type} for order {stored.order_id}",
                {"order_id": stored.order_id, "razorpay_order_id": order_id,
                 "payment_id": payment_id},
            )

    return {"status": "ok"}



if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=False)