"""Optional Anthropic provider for the Waflo Builder.

Not enabled by default. To use it set ``BUILDER_LLM_PROVIDER=anthropic`` in the
backend ``.env`` (plus ``ANTHROPIC_API_KEY``). Falls back to the Waflo chain
if Anthropic is not actually configured.
"""

from __future__ import annotations

import logging
import os
from typing import Optional

from .llm_provider import LLMProvider

logger = logging.getLogger(__name__)


class ClaudeLLMProvider(LLMProvider):
    def __init__(self, max_tokens: int = 12000) -> None:
        self._api_key = (
            os.environ.get("ANTHROPIC_API_KEY")
            or os.environ.get("ANTHROPIC_KEY")
            or ""
        )
        self._max_tokens = max_tokens

    def complete(self, prompt: str, system: Optional[str] = None) -> str:
        if not self._api_key:
            raise RuntimeError(
                "ANTHROPIC_API_KEY is not set; check the Anthropic "
                "provider configuration"
            )
        try:
            from anthropic import Anthropic
        except Exception as e:
            raise RuntimeError(f"anthropic SDK not installed: {e}") from e

        client = Anthropic(api_key=self._api_key)
        kwargs: dict = {
            "model": "claude-3-7-sonnet-latest",
            "max_tokens": self._max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if system:
            kwargs["system"] = system
        response = client.messages.create(**kwargs)
        text = "".join(
            block.text for block in response.content if getattr(block, "type", "") == "text"
        ).strip()
        if not text:
            raise RuntimeError("Anthropic returned an empty completion")
        return text