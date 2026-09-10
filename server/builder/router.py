"""Waflo Builder HTTP + WebSocket routes.

Additive to the main app — registers on two routers:
- ``builder_router`` (prefix ``/api/builder``) for the REST API
- ``builder_socket_router`` (``/ws/builder``) for live progress events
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response

from builder.schemas import (
    BuilderCancelResponse,
    BuilderFileResponse,
    BuilderGenerateRequest,
    BuilderGenerateResponse,
    BuilderJobStatus,
    BuilderJobView,
    BuilderProjectMeta,
)
from builder.service import builder_service

logger = logging.getLogger(__name__)

_PREVIEW_MEDIA_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".htm": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json",
    ".map": "application/json",
    ".txt": "text/plain; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".avif": "image/avif",
    ".ico": "image/x-icon",
    ".bmp": "image/bmp",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
    ".eot": "application/vnd.ms-fontobject",
    ".webmanifest": "application/manifest+json",
}


def _preview_media_type(rel: str) -> str:
    dot = rel.rfind(".")
    if dot == -1:
        return "text/html; charset=utf-8"
    return _PREVIEW_MEDIA_TYPES.get(
        rel[dot:].lower(), "application/octet-stream"
    )

router = APIRouter(prefix="/api/builder", tags=["builder"])
socket_router = APIRouter(tags=["builder"])


@router.get("/health")
def builder_health() -> dict:
    return {"status": "ok"}


@router.post("/generate", response_model=BuilderGenerateResponse)
async def generate(body: BuilderGenerateRequest) -> BuilderGenerateResponse:
    """Create a Builder job. Live progress arrives on the WebSocket
    (subscribe with ``{"action": "subscribe", "job_id": ...}``) or by polling
    ``GET /api/builder/jobs/<job_id>``.

    Async endpoint: BuilderService.start() schedules the job via
    ``asyncio.create_task`` which needs a running event loop.
    """
    job_id = builder_service.start(
        prompt=body.prompt, mode=body.mode, url=body.url
    )
    return BuilderGenerateResponse(job_id=job_id)


@router.get("/jobs/{job_id}", response_model=BuilderJobView)
def get_job(job_id: str) -> BuilderJobView:
    job = builder_service.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Builder job not found")
    return job


@router.post("/jobs/{job_id}/cancel", response_model=BuilderCancelResponse)
async def cancel_job(job_id: str) -> BuilderCancelResponse:
    cancelled = builder_service.cancel(job_id)
    if not cancelled:
        existing = builder_service.get_job(job_id)
        if existing is None:
            raise HTTPException(status_code=404, detail="Builder job not found")
    return BuilderCancelResponse(job_id=job_id, cancelled=cancelled)


@router.get("/projects", response_model=list[BuilderProjectMeta])
def list_projects() -> list[BuilderProjectMeta]:
    return builder_service.list_projects()


@router.get("/projects/{project_id}", response_model=BuilderProjectMeta)
def get_project(project_id: str) -> BuilderProjectMeta:
    meta = builder_service.get_project(project_id)
    if meta is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return meta


@router.get(
    "/projects/{project_id}/file",
    response_model=BuilderFileResponse,
)
def get_project_file(project_id: str, path: str) -> BuilderFileResponse:
    content = builder_service.read_project_file(project_id, path)
    if content is None:
        raise HTTPException(status_code=404, detail="Project file not found")
    return BuilderFileResponse(project_id=project_id, path=path, content=content)


@router.get("/projects/{project_id}/preview")
@router.get("/projects/{project_id}/preview/{path:path}")
def project_preview(project_id: str, path: str = "") -> Response:
    """Serve a generated project over HTTP so it can be embedded live (iframe)
    or opened in a browser. ``/…/preview/`` and ``/…/preview/index.html`` both
    resolve to the site's ``index.html``; missing ``.html`` pages fall back to
    ``index.html`` like a static-site host. ``preview_dir`` is unused — the
    source is the render target."""
    rel = path.lstrip("/")
    if not rel or rel.endswith("/"):
        rel = "index.html"
    data = builder_service.read_project_bytes(
        project_id, rel, fallback_index=True
    )
    if data is None:
        raise HTTPException(status_code=404, detail="Preview file not found")
    return Response(
        content=data,
        media_type=_preview_media_type(rel),
        headers={"Cache-Control": "no-store"},
    )


@socket_router.websocket("/ws/builder")
async def builder_websocket_endpoint(websocket: WebSocket) -> None:
    """Live builder progress. Client subscribes with one JSON message:
    ``{"action": "subscribe", "job_id": "<id>"}``. The server replies with a
    ``snapshot`` of the current state, then streams ``progress`` events until
    the job reaches a terminal status (completed / failed / cancelled)."""
    await websocket.accept()
    job_id: str | None = None
    try:
        msg = await websocket.receive_json()
        if isinstance(msg, dict) and msg.get("action") == "subscribe":
            job_id = msg.get("job_id")
        if not job_id or builder_service.get_job(job_id) is None:
            await websocket.send_json(
                {"type": "error", "message": "Unknown builder job"}
            )
            await websocket.close()
            return

        builder_service.subscribe(job_id, websocket)
        await builder_service.send_snapshot(job_id, websocket)

        # Keep the socket open. Progress events are pushed from the background
        # generation task; this loop only watches for a client unsubscribe or
        # disconnect so the subscription can be cleaned up.
        while True:
            incoming = await websocket.receive_json()
            if isinstance(incoming, dict) and incoming.get("action") in (
                "unsubscribe",
                "ping",
            ):
                await websocket.send_json({"type": "pong"})
            else:
                await websocket.send_json(
                    {"type": "error", "message": "Unsupported action"}
                )
    except WebSocketDisconnect:
        pass
    except Exception as e:  # pragma: no cover - defensive
        logger.warning("Builder WS error: %s", e)
    finally:
        builder_service.unsubscribe(job_id, websocket)