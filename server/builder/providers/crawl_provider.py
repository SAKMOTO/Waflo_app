"""URL-analysis (crawl) abstraction for the Waflo Builder.

Mode ``url`` analyses a live site before generating. The default provider
reuses Waflo's existing Firecrawl adapter (``services/firecrawl_service.py``)
which wraps the vendored Firecrawl SDK — no duplicate keys, no secrets here.

Rules from the Builder spec are enforced in the SERVICE layer, not here:
- Only layout/structure/typography/colors/sections/components are analysed.
- The generated project is an INDEPENDENT implementation; it never copies
  protected branding, logos or source code, and never claims to be a clone.
"""

from __future__ import annotations

import abc
import logging

logger = logging.getLogger(__name__)


class CrawlProviderError(RuntimeError):
    """Safe-to-log crawl failure (never contains a key)."""


class CrawlProvider(abc.ABC):
    @abc.abstractmethod
    async def scrape(self, url: str) -> str:
        """Return a bounded, content-only dump of the page suitable for an LLM."""


class FirecrawlCrawlProvider(CrawlProvider):
    def __init__(self, service=None) -> None:
        if service is None:
            from services.firecrawl_service import FirecrawlService

            service = FirecrawlService()
        self._service = service

    async def scrape(self, url: str) -> str:
        try:
            rec = await self._service.scrape_url(url, timeout_ms=30000)
        except Exception as e:
            raise CrawlProviderError(f"Could not analyse {url}: {e}") from e
        content = (rec.get("content") or "").strip()
        if not content:
            raise CrawlProviderError(f"Firecrawl returned no readable content for {url}")
        if len(content) > 4000:
            content = content[:4000].rstrip() + "\n…\n"
        return content


def default_crawl_provider():
    try:
        from services.firecrawl_service import FirecrawlService

        svc = FirecrawlService()
        if svc.is_available:
            return FirecrawlCrawlProvider(svc)
    except Exception as e:  # pragma: no cover - environment dependent
        logger.info("Builder crawl provider unavailable (%s)", e)
    return None