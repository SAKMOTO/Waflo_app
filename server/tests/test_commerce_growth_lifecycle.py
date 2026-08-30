"""Regression tests for the cross-sell / upsell growth-agent lifecycle.

The main search task sets active_tasks[task_id] = False when it completes, which
made the growth sub-agent's should_stop_callback stop it at step 0 ("External
callback requested stop") and return 0 products/accessories. cross_sell() and
upsell() must now re-activate the task for the duration of the run, emit the
product + growth_result events, and restore the flag afterwards.
"""

import asyncio

from pydantic_models.commerce_models import ProductInfo
from services.commerce_agent_service import CommerceAgentService

svc = CommerceAgentService()


def _run(coro):
    return asyncio.run(coro)


async def _stubbed_run(task_id, prompt, event_callback):
    prompts.append(prompt)
    return [ProductInfo(name="Redragon Wrist Rest", price=449.0, source_url="live")]


prompts = []


def test_cross_sell_runs_agent_and_restores_active():
    svc.active_tasks["t-growth"] = False  # simulate completed main search
    sent = []

    async def fake_send(cb, event):
        d = event if isinstance(event, dict) else event.model_dump()
        sent.append(d.get("growth_type") or d.get("type"))

    orig_run, orig_send, orig_get = svc._run_targeted_task, svc._send_event, svc._get_task_product
    svc._run_targeted_task = _stubbed_run
    svc._send_event = fake_send
    svc._get_task_product = lambda tid, i: ProductInfo(
        name="Cosmic Byte CB-GK-43", price=2999.0, source_url="live"
    )
    try:
        ok = _run(svc.cross_sell("t-growth", 0, None))
    finally:
        svc._run_targeted_task, svc._send_event, svc._get_task_product = orig_run, orig_send, orig_get

    assert ok is True
    assert svc.active_tasks["t-growth"] is False  # restored afterwards
    assert "cross_sell" in sent
    assert prompts and "individual product page" in prompts[0]


def test_upsell_runs_agent_and_restores_active():
    svc.active_tasks["t-growth"] = False
    sent = []

    async def fake_send(cb, event):
        d = event if isinstance(event, dict) else event.model_dump()
        sent.append(d.get("growth_type") or d.get("type"))

    orig_run, orig_send, orig_get = svc._run_targeted_task, svc._send_event, svc._get_task_product
    svc._run_targeted_task = _stubbed_run
    svc._send_event = fake_send
    svc._get_task_product = lambda tid, i: ProductInfo(
        name="Cosmic Byte CB-GK-43", price=2999.0, source_url="live"
    )
    svc.task_data["t-growth"] = {"intent": {"max_budget": 3000.0}, "query": "headphones"}
    try:
        ok = _run(svc.upsell("t-growth", 0, None))
    finally:
        svc._run_targeted_task, svc._send_event, svc._get_task_product = orig_run, orig_send, orig_get

    assert ok is True
    assert svc.active_tasks["t-growth"] is False
    assert "upsell" in sent
    assert prompts and "individual product page" in prompts[-1]