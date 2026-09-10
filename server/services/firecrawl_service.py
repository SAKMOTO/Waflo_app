"""Firecrawl adapter for the ARIA research brain.

Wraps the **vendored** Firecrawl Python SDK (``<repo>/firecrawl/apps/python-sdk``,
firecrawl-py v4.41.0) behind a small, safe async interface:

- It owns NO client secrets. The API key stays in backend settings and is only
  used to authenticate outbound calls to the configured Firecrawl endpoint
  (cloud or self-hosted). Nothing here is ever forwarded to the Flutter client.
- Every public method is async and runs the blocking SDK call in a worker
  thread so the FastAPI event loop is never blocked.
- Every failure degrades cleanly: callers catch :class:`FirecrawlError` and fall
  back to browser-use research, so ARIA keeps working without Firecrawl.

Only a deliberately small subset of the SDK is used (search / scrape / map).
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional, Sequence
from urllib.parse import urlparse

from config import Settings
from vendor_firecrawl import IS_FIRECRAWL_PRESENT, bootstrap_vendored_firecrawl

logger = logging.getLogger(__name__)


class FirecrawlError(RuntimeError):
    """Raised when a Firecrawl call fails. Message is safe to log, never a key."""


def _domain_of(url: str) -> str:
    try:
        return urlparse(url).netloc.lower() or ""
    except Exception:
        return ""


def _attr(obj, *names):
    """First non-empty attribute value across a sequence of names."""
    for name in names:
        try:
            value = getattr(obj, name)
        except Exception:
            continue
        if value:
            return value
    return None


def normalize_search_result(item: object) -> dict:
    """Normalize one SearchData result (SearchResultWeb/News/Images or Document).

    Produces a plain dict with keys ``url``, ``title``, ``content``, ``domain``.
    """
    url = _attr(item, "url", "href") or ""
    title = _attr(item, "title") or None
    content = _attr(item, "markdown", "summary") or None
    if not content:
        content = _attr(item, "description", "snippet") or None
    if not url:
        return {}
    content = str(content).strip() if content else ""
    if len(content) > 1200:
        content = content[:1200].rstrip() + "…"
    return {
        "url": url,
        "title": (str(title) if title else None),
        "content": content,
        "domain": _domain_of(url),
    }


def normalize_document(doc: object) -> dict:
    """Normalize a Firecrawl scraped Document into a plain dict."""
    url = _attr(doc, "url", "source_url") or ""
    markdown = str(_attr(doc, "markdown") or "").strip()
    summary = _attr(doc, "summary")
    metadata = getattr(doc, "metadata", None) or {}
    title = None
    if isinstance(metadata, dict):
        title = metadata.get("title") or metadata.get("og_title")
    else:
        title = _attr(metadata, "title", "og_title")
    content = markdown or (str(summary).strip() if summary else "")
    if len(content) > 4000:
        content = content[:4000].rstrip() + "…"
    return {
        "url": url,
        "title": (str(title) if title else None),
        "content": content,
        "domain": _domain_of(url),
    }


class FirecrawlService:
    """Async adapter over the vendored Firecrawl SDK (search/scrape/map)."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        api_url: Optional[str] = None,
    ) -> None:
        self._client = None
        self._api_key = api_key
        self._api_url = api_url

    # ------------------------------------------------------------------
    # Availability & client
    # ------------------------------------------------------------------

    @property
    def is_available(self) -> bool:
        settings = Settings()
        configured = bool(
            self._api_key or settings.FIRECRAWL_API_KEY
        ) or bool(self._api_url or settings.FIRECRAWL_API_URL)
        return IS_FIRECRAWL_PRESENT and configured

    @property
    def endpoint_label(self) -> str:
        settings = Settings()
        return self._api_url or settings.FIRECRAWL_API_URL or "https://api.firecrawl.dev"

    def _build_client(self):
        bootstrap_vendored_firecrawl()
        try:
            # The v2 client is the SDK's main class (top-level `firecrawl`
            # exports the older FirecrawlApp-style facade).
            from firecrawl.v2.client import FirecrawlClient  # vendored SDK
        except Exception as exc:  # pragma: no cover - environment dependent
            raise FirecrawlError(f"Firecrawl SDK is not importable: {exc}")
        settings = Settings()
        kwargs: dict = {
            "api_key": self._api_key or settings.FIRECRAWL_API_KEY or None,
            "timeout": 60,
            "max_retries": 2,
            "backoff_factor": 0.5,
        }
        api_url = self._api_url or settings.FIRECRAWL_API_URL
        if api_url:
            # ClientConfig.api_url is a plain str; only set it when configured so
            # the SDK's own default (https://api.firecrawl.dev) applies.
            kwargs["api_url"] = api_url
        return FirecrawlClient(**kwargs)

    @property
    def client(self):
        if self._client is not None:
            return self._client
        if not self.is_available:
            raise FirecrawlError(
                "Firecrawl is not configured: set FIRECRAWL_API_KEY / "
                "FIRECRAWL_API_URL (cloud or self-hosted), or the vendored SDK "
                "folder is missing."
            )
        self._client = self._build_client()
        return self._client

    # ------------------------------------------------------------------
    # Research methods
    # ------------------------------------------------------------------

    async def search_web(
        self,
        query: str,
        include_domains: Optional[Sequence[str]] = None,
        limit: int = 6,
    ) -> list[dict]:
        """Search the web and return normalized results (plain dicts)."""
        domain_filter = [d for d in (include_domains or []) if d][:5] or None
        kwargs: dict = {"limit": max(1, min(int(limit), 10))}
        if domain_filter:
            kwargs["include_domains"] = domain_filter
        client = self.client
        try:
            response = await asyncio.to_thread(client.search, query, **kwargs)
        except Exception as exc:
            raise FirecrawlError(f"Firecrawl search failed for {domain_filter or 'web'}: {exc}") from exc

        results: list[dict] = []
        seen_urls: set[str] = set()
        for group in (
            list(getattr(response, "web", None) or []),
            list(getattr(response, "news", None) or []),
        ):
            for item in group:
                rec = normalize_search_result(item)
                url = rec.get("url", "")
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)
                results.append(rec)
        logger.info(
            "[ARIA FIRECRAWL] search query=%r limit=%s domains=%s -> %d unique results",
            query, limit, domain_filter, len(results),
        )
        return results

    async def scrape_url(
        self,
        url: str,
        timeout_ms: Optional[int] = None,
    ) -> dict:
        """Scrape a single URL into a normalized plain dict."""
        client = self.client
        try:
            doc = await asyncio.to_thread(
                client.scrape, url, formats=["markdown"], timeout=timeout_ms or 30000,
            )
        except Exception as exc:
            raise FirecrawlError(f"Firecrawl scrape failed for {_domain_of(url)}: {exc}") from exc
        rec = normalize_document(doc)
        logger.info("[ARIA FIRECRAWL] scrape url=%s -> %d chars", url, len(rec.get("content") or ""))
        return rec

    async def map_links(self, url: str, limit: int = 20) -> list[str]:
        """Discover internal links of a site (Firecrawl ``map``)."""
        client = self.client
        try:
            response = await asyncio.to_thread(client.map, url=url, limit=max(1, min(int(limit), 100)))
        except Exception as exc:
            raise FirecrawlError(f"Firecrawl map failed for {_domain_of(url)}: {exc}") from exc
        links = list(getattr(response, "links", None) or [])
        links = [l for l in links if l]
        logger.info("[ARIA FIRECRAWL] map url=%s -> %d links", url, len(links))
        return links[:limit]

    async def crawl_web(
        self,
        url: str,
        max_pages: int = 4,
        max_depth: int = 1,
    ) -> list[dict]:
        """Lightweight crawl: map the site, then scrape the top ``max_pages`` links.

        A full Firecrawl ``crawl`` is a long-running background job; for research
        ETAs a bounded map + targeted scrapes gives the same result quickly and
        fits the research budget. ``max_pages`` is always capped.
        """
        budget = max(1, min(int(max_pages), 6))
        links = await self.map_links(url, limit=budget * 3)
        scraped: list[dict] = []
        for link in links[:budget]:
            try:
                doc = await self.scrape_url(link)
            except FirecrawlError:
                continue
            if doc and doc.get("content"):
                scraped.append(doc)
        return scraped

    async def close(self) -> None:  # pragma: no cover - no socket held by the SDK
        self._client = None