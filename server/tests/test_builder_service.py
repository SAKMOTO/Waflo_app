"""Tests for the Waflo Builder (isolated project generation).

Run with:  ./venv/bin/python -m pytest tests/test_builder_service.py -q
"""

import asyncio
import threading

import pytest
from pydantic import ValidationError

from builder import service as builder_module
from builder.schemas import BuilderGenerateRequest
from builder.service import BuilderService, _safe_rel_path, parse_file_blocks, parse_plan


def test_parser_extracts_file_blocks():
    text = (
        "<file path=\"index.html\"><h1>hi</h1></file>"
        "<file path='style.css'>body{}</file>"
        "<file path=\"nested/app.js\">console.log(1)</file>"
    )
    files = parse_file_blocks(text)
    assert files["index.html"] == "<h1>hi</h1>"
    assert files["style.css"] == "body{}"
    assert files["nested/app.js"] == "console.log(1)"


def test_parser_prefers_duplicate_complete_version():
    text = (
        '<file path="a.html">short</file>'
        '<file path="a.html">complete version</file>'
    )
    files = parse_file_blocks(text)
    assert files["a.html"] == "complete version"


def test_parser_extracts_plan_and_falls_back():
    assert "TITLE: X" in parse_plan(
        "intro<plan>TITLE: X\nPAGES: one</plan>outro"
    )
    raw = parse_plan("no plan tags, just ideas here")
    assert "no plan tags" in raw


def test_safe_rel_path_blocks_traversal():
    assert _safe_rel_path("../evil/../../x.txt") == "evil/x.txt"
    assert _safe_rel_path("/etc/passwd") == "etc/passwd"
    assert _safe_rel_path(".\\..\\..\\boom") == "boom"
    assert _safe_rel_path("../..") == ""


def test_generate_request_rejects_short_prompt():
    with pytest.raises(ValidationError):
        BuilderGenerateRequest(prompt="short")


def test_generate_request_accepts_url_mode():
    req = BuilderGenerateRequest(
        prompt="Rebuild a nice landing page", mode="url",
        url="https://example.com",
    )
    assert req.mode == "url"
    assert req.url == "https://example.com"


def test_project_meta_never_serializes_secrets():
    from builder.schemas import BuilderProjectMeta

    meta = BuilderProjectMeta(
        project_id="p1", title="t", prompt="p", created_at="now",
        updated_at="now",
    )
    dumped = meta.model_dump()
    for key in ("api_key", "secret", "token", "password"):
        assert key not in dumped


async def _run_pipeline(tmp_root, llm_stub, prompt="Build a landing page"):
    builder_module.GENERATED_ROOT = tmp_root
    svc = BuilderService()
    svc._llm = llm_stub
    svc._crawl = None
    job_id = svc.start(prompt)
    for _ in range(100):
        view = svc.get_job(job_id)
        if view.status in ("completed", "failed", "cancelled"):
            return view
        await asyncio.sleep(0.05)
    return svc.get_job(job_id)


def test_pipeline_completes_and_persists(tmp_path):
    class Stub:
        def complete(self, prompt, system=None):
            if "Create a detailed build plan" in prompt:
                return "<plan>TITLE: Cool Landing\nPAGES: Hero, features</plan>"
            return (
                '<file path="index.html"><!doctype html><h1>Cool</h1></file>'
                '<file path="style.css">body{}</file>'
            )

    view = asyncio.run(_run_pipeline(tmp_path, Stub()))
    assert view.status == "completed", view.error
    assert view.error is None
    assert view.project is not None
    assert view.project.title == "Cool Landing"
    assert "index.html" in view.project.files


def test_pipeline_fails_cleanly_when_no_files(tmp_path):
    class Stub:
        def complete(self, prompt, system=None):
            if "Create a detailed build plan" in prompt:
                return "<plan>TITLE: T</plan>"
            return "No file blocks here at all."

    view = asyncio.run(_run_pipeline(tmp_path, Stub()))
    assert view.status == "failed"
    assert view.error and "files" in view.error.lower()


def test_cancel_mid_generation(tmp_path):
    class BlockingStub:
        def __init__(self):
            self.unblock = threading.Event()

        def complete(self, prompt, system=None):
            self.unblock.wait(5)
            if "Create a detailed build plan" in prompt:
                return "<plan>TITLE: T</plan>"
            return '<file path="index.html">x</file>'

    stub = BlockingStub()

    async def scenario():
        builder_module.GENERATED_ROOT = tmp_path
        svc = BuilderService()
        svc._crawl = None
        job_id = svc.start("Build something")
        await asyncio.sleep(0.1)
        cancelled = svc.cancel(job_id)
        stub.unblock.set()
        for _ in range(100):
            job = svc.get_job(job_id)
            if job.status in ("completed", "failed", "cancelled"):
                return job, cancelled
            await asyncio.sleep(0.05)

    job, cancelled_ok = asyncio.run(scenario())
    assert cancelled_ok is True
    assert job.status == "cancelled"