"""LLM provider abstraction for the Waflo Builder.

The Builder reuses Waflo's EXISTING provider configuration (`server/config.py`
+ `.env`) — the same API keys and the same fallback order (local Ollama ->
OpenRouter -> Gemini -> Hugging Face) used by ``services/llm_service.py``.

Unlike the chat service (streaming, ~1200 tokens) the Builder needs long,
deterministic completions (a plan, then the generated files), so it exposes a
plain ``complete(prompt) -> str`` that collects a full non-streaming answer
with a generous token budget. No secrets are ever exposed by this module; the
keys stay in backend settings only.
"""

from __future__ import annotations

import abc
import logging
import os
import time
from typing import Optional

os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")

logger = logging.getLogger(__name__)

# A wall-clock deadline for a single streaming completion. Without this, a
# provider (notably local Ollama) whose stream never closes holds the worker
# thread forever and the job wedges at "generating".
STREAM_TIMEOUT_SECONDS = float(os.environ.get("BUILDER_LLM_TIMEOUT", "240"))


class LLMProvider(abc.ABC):
    @abc.abstractmethod
    def complete(self, prompt: str, system: Optional[str] = None) -> str:
        """Return a full completion for `prompt`. Raises RuntimeError on
        unfixable provider failure so the Builder job can fail gracefully."""


class WafloLLMProvider(LLMProvider):
    """Reuses settings/config from the parent Waflo backend. Lazily builds
    clients on first use so importing the Builder never slows boot.

    The Builder uses the LOCAL Ollama model FIRST (free, unlimited, no rate
    limits) and only falls back to the cloud chain (OpenRouter -> Gemini ->
    Hugging Face) when Ollama is not running. Set ``BUILDER_SKIP_OLLAMA=true``
    in the backend .env to force the cloud chain instead.
    """

    def __init__(self, max_tokens: int = 12000) -> None:
        from config import Settings

        self._settings = Settings()
        self._max_tokens = max_tokens
        self._use_ollama = (
            os.environ.get("BUILDER_SKIP_OLLAMA", "").strip().lower()
            not in ("1", "true", "yes", "on")
        )
        self._clients = None

    # ------------------------------------------------------------------
    # Client init (lazy, mirrors services/llm_service.py)
    # ------------------------------------------------------------------

    def _init_clients(self) -> dict:
        if self._clients is not None:
            return self._clients

        s = self._settings
        clients: dict = {
            "ollama": None,
            "openrouter": None,
            "gemini": None,
            "hf": None,
        }

        if self._use_ollama:
            import urllib.request

            try:
                with urllib.request.urlopen(
                    "http://localhost:11434/api/tags", timeout=2
                ):
                    from openai import OpenAI

                    clients["ollama"] = {
                        "client": OpenAI(
                            base_url="http://localhost:11434/v1",
                            api_key="ollama",
                        ),
                        "model": getattr(s, "OLLAMA_MODEL", "") or "qwen3:4b",
                    }
                    logger.info("Builder LLM: local Ollama available (preferred)")
            except Exception as e:
                logger.info("Builder LLM: Ollama not available (%s)", e)

        if s.OPENROUTER_API_KEY:
            try:
                from openai import OpenAI

                clients["openrouter"] = {
                    "client": OpenAI(
                        base_url="https://openrouter.ai/api/v1",
                        api_key=s.OPENROUTER_API_KEY,
                    ),
                    # OpenRouter default: a currently-available `:free` model.
                    # Older defaults (minimax/minimax-m3:free) were retired (404)
                    # / returned no output; this Nemotron free model works.
                    "model": getattr(s, "OPENROUTER_MODEL", "") or "nvidia/nemotron-3-super-120b-a12b:free",
                }
                logger.info("Builder LLM: OpenRouter configured")
            except Exception as e:
                logger.warning("Builder LLM: OpenRouter init failed: %s", e)

        if s.GEMINI_API_KEY:
            try:
                from google import genai

                clients["gemini"] = {
                    "client": genai.Client(api_key=s.GEMINI_API_KEY),
                    "model": "gemini-3.6-flash",
                }
                logger.info("Builder LLM: Gemini configured")
            except Exception as e:
                logger.warning("Builder LLM: Gemini init failed: %s", e)

        if s.HF_TOKEN:
            try:
                from huggingface_hub import InferenceClient

                clients["hf"] = {
                    "client": InferenceClient(api_key=s.HF_TOKEN),
                    "model": "Qwen/Qwen2.5-72B-Instruct",
                }
                logger.info("Builder LLM: Hugging Face configured")
            except Exception as e:
                logger.warning("Builder LLM: HF init failed: %s", e)

        self._clients = clients
        return clients

    def complete(self, prompt: str, system: Optional[str] = None) -> str:
        clients = self._init_clients()
        failures: list[str] = []

        if clients["ollama"] is not None:
            try:
                return self._complete_with("ollama", self._ollama, prompt, system, clients["ollama"])
            except Exception as e:
                failures.append(f"ollama: {e}")
        # Gemini first: it is the most reliable provider for this account (the
        # OpenRouter `:free` models were retired, so OpenRouter would otherwise
        # 404 on every single call before we even reach a working provider).
        # `_gemini` retries transient 503/429 quota errors with backoff.
        if clients["gemini"] is not None:
            try:
                return self._complete_with("gemini", self._gemini, prompt, system, clients["gemini"])
            except Exception as e:
                failures.append(f"gemini: {e}")
        if clients["hf"] is not None:
            try:
                return self._complete_with("hf", self._hf, prompt, system, clients["hf"])
            except Exception as e:
                failures.append(f"hf: {e}")
        if clients["openrouter"] is not None:
            try:
                return self._complete_with("openrouter", self._openrouter, prompt, system, clients["openrouter"])
            except Exception as e:
                failures.append(f"openrouter: {e}")

        raise RuntimeError(
            "No LLM provider could reach a model. Set GEMINI_API_KEY or "
            "HF_TOKEN in the backend .env. "
            "(" + "; ".join(failures)[:300] + ")"
        )

    def _complete_with(self, name: str, fn, prompt: str, system, entry: dict) -> str:
        logger.info("Builder LLM: calling %s…", name)
        text = fn(prompt, system, entry)
        logger.info("Builder LLM: %s returned %d chars", name, len(text))
        return text

    # ------------------------------------------------------------------
    # Per-provider implementations
    # ------------------------------------------------------------------

    def _ollama(self, prompt: str, system: Optional[str], entry: dict):
        messages = self._messages(prompt, system)
        stream = entry["client"].chat.completions.create(
            model=entry["model"],
            messages=messages,
            max_tokens=self._max_tokens,
            stream=True,
        )
        text = self._collect_stream(stream).strip()
        if not text:
            raise RuntimeError("Ollama returned an empty completion")
        return text

    def _openrouter(self, prompt: str, system: Optional[str], entry: dict):
        messages = self._messages(prompt, system)
        stream = entry["client"].chat.completions.create(
            model=entry["model"],
            messages=messages,
            max_tokens=self._max_tokens,
            temperature=0.3,
            stream=True,
            extra_headers={
                "HTTP-Referer": "http://127.0.0.1:8000",
                "X-Title": "Waflo Builder",
            },
        )
        text = self._collect_stream(stream).strip()
        if not text:
            raise RuntimeError("OpenRouter returned an empty completion")
        return text

    def _gemini(self, prompt: str, system: Optional[str], entry: dict):
        contents = prompt
        config: dict = {
            "max_output_tokens": self._max_tokens,
            "temperature": 0.3,
        }
        if system:
            config["system_instruction"] = system
        last_error: Optional[Exception] = None
        response = None
        for attempt in range(3):
            try:
                response = entry["client"].models.generate_content(
                    model=entry["model"], contents=contents, config=config
                )
                break
            except Exception as e:
                last_error = e
                msg = str(e)
                if "503" in msg or "429" in msg or "unavailable" in msg.lower():
                    time.sleep(2 * (attempt + 1))
                    continue
                raise
        if response is None:
            raise RuntimeError(f"Gemini unavailable: {last_error}")
        text = (response.text or "").strip()
        if not text:
            raise RuntimeError("Gemini returned an empty completion")
        return text

    def _hf(self, prompt: str, system: Optional[str], entry: dict):
        content: list[dict] = [{"type": "text", "text": prompt}]
        if system:
            content.insert(0, {"type": "text", "text": system})
        messages = [
            {"role": "user", "content": [{"type": "text", "text": prompt}]}
        ]
        stream = entry["client"].chat_completion(
            model=entry["model"],
            messages=messages,
            max_tokens=self._max_tokens,
            stream=True,
        )
        text = self._collect_stream(stream).strip()
        if not text:
            raise RuntimeError("Hugging Face returned an empty completion")
        return text

    @staticmethod
    def _collect_stream(stream) -> str:
        """Consume a streaming completion, aborting if it never closes."""
        started = time.monotonic()
        out: list[str] = []
        for chunk in stream:
            if time.monotonic() - started > STREAM_TIMEOUT_SECONDS:
                raise RuntimeError(
                    f"LLM stream did not finish within {int(STREAM_TIMEOUT_SECONDS)}s"
                )
            if chunk.choices and chunk.choices[0].delta.content:
                out.append(chunk.choices[0].delta.content)
        return "".join(out)

    @staticmethod
    def _messages(prompt: str, system: Optional[str]) -> list[dict]:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})
        return messages


def default_llm_provider() -> LLMProvider:
    provider = os.environ.get("BUILDER_LLM_PROVIDER", "").lower().strip()

    if provider and provider != "waflo":
        try:
            from .llm_claude import ClaudeLLMProvider

            if provider == "anthropic":
                return ClaudeLLMProvider()
        except Exception as e:  # pragma: no cover - optional provider
            logger.warning("Builder LLM: requested provider %r unavailable (%s), using Waflo chain", provider, e)

    return WafloLLMProvider()