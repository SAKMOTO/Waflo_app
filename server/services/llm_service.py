import os

from dotenv import load_dotenv

from config import Settings

load_dotenv()

settings = Settings()


class LLMService:
    def __init__(self):
        self.model_name = "gemini-3.6-flash"
        self._ollama_client = None
        self._ollama_model = getattr(settings, "OLLAMA_MODEL", "") or "qwen3:4b"
        self._openrouter_client = None
        # OpenRouter default: a currently-available `:free` model. The older
        # defaults (minimax/minimax-m3:free) were retired (404) / returned no
        # output; nvidia/nemotron-3-super-120b-a12b:free worked in testing.
        self._openrouter_model = getattr(settings, "OPENROUTER_MODEL", "") or (
            "nvidia/nemotron-3-super-120b-a12b:free"
        )
        self._gemini_client = None
        self._hf_client = None
        self._hf_model = "Qwen/Qwen2.5-72B-Instruct"
        self._init_clients()

    def _init_clients(self):
        """Prefer the LOCAL Ollama model (free, unlimited, no rate limits),
        then OpenRouter (free models), then Gemini, then Hugging Face."""
        import urllib.request

        try:
            with urllib.request.urlopen(
                "http://localhost:11434/api/tags", timeout=2
            ):
                from openai import OpenAI

                self._ollama_client = OpenAI(
                    base_url="http://localhost:11434/v1",
                    api_key="ollama",  # required by SDK, ignored locally
                )
                print(f"✅ LLMService initialized with local Ollama ({self._ollama_model})")
        except Exception as e:
            print(f"Ollama not available (fallback to cloud providers): {e}")
        if settings.OPENROUTER_API_KEY:
            try:
                from openai import OpenAI

                self._openrouter_client = OpenAI(
                    base_url="https://openrouter.ai/api/v1",
                    api_key=settings.OPENROUTER_API_KEY,
                )
                print("✅ LLMService initialized with OpenRouter")
            except Exception as e:
                print(f"Failed to initialize OpenRouter in LLMService: {e}")
        if settings.GEMINI_API_KEY:
            try:
                from google import genai

                self._gemini_client = genai.Client(api_key=settings.GEMINI_API_KEY)
                print("✅ LLMService initialized with Gemini")
            except Exception as e:
                print(f"Failed to initialize Gemini in LLMService: {e}")
        if settings.HF_TOKEN:
            try:
                from huggingface_hub import InferenceClient

                self._hf_client = InferenceClient(api_key=settings.HF_TOKEN)
                print("✅ LLMService initialized with Hugging Face")
            except Exception as e:
                print(f"Failed to initialize HF in LLMService: {e}")

    def generate_response(self, query: str, search_results: list[dict], file_name: str = None, file_base64: str = None):
        context_text = "\n\n".join(
            [
                f"""Source {i + 1} ({result.get('url', '')}):
                Content: {result.get('content', '')}"""
                for i, result in enumerate(search_results)
            ]
        )
        has_context = context_text.strip() != ""

        if has_context:
            prompt = f"""
You are Waflo, an advanced AI assistant. Answer the user's query in a clear, helpful, conversational way.

Relevant web context (if useful, cite it; otherwise rely on your own knowledge):
{context_text}

Query: {query}

Provide a natural, useful, accurate response. You may use your own knowledge to answer; the web context is only supporting material where relevant. If the context contradicts what you know, prefer information from the context.
"""
        else:
            prompt = f"""
You are Waflo, an advanced AI assistant. Answer the user's query in a clear, helpful, conversational way, exactly like a general-purpose chatbot (e.g., ChatGPT).

Query: {query}

Provide a natural, useful, accurate response based on your own knowledge.
"""

        if self._ollama_client is not None:
            # Local model first: 100% free, unlimited, no rate limits.
            try:
                print("🤖 Provider: LOCAL Ollama")
                for c in self._generate_ollama(prompt):
                    yield c
                return
            except Exception as e:
                print(f"Ollama Error, falling back to cloud providers: {e}")

        # Gemini first (fast, and its generator already retries transient 503/429
        # quota errors). It falls through to Hugging Face when unavailable.
        if self._gemini_client is not None:
            chunks = list(self._generate_gemini(prompt))
            if chunks and not chunks[0].startswith("__FALLBACK__"):
                for c in chunks:
                    yield c
                return
            if self._hf_client is not None:
                try:
                    for c in self._generate_hf(prompt):
                        yield c
                    return
                except Exception as e:
                    print(f"Hugging Face Error, falling back to OpenRouter: {e}")
            else:
                for c in chunks:
                    yield self._friendly_fallback(c)
                return

        if self._hf_client is not None:
            try:
                yield from self._generate_hf(prompt)
                return
            except Exception as e:
                print(f"Hugging Face Error, falling back to OpenRouter: {e}")

        if self._openrouter_client is not None:
            # OpenRouter last resort: the account's `:free` models have been
            # retired, so this only succeeds for paid slugs with credit.
            try:
                print("🌐 Provider: OpenRouter")
                for c in self._generate_openrouter(prompt):
                    yield c
                return
            except Exception as e:
                print(f"OpenRouter Error: {e}")

        yield "\n\n[No LLM provider could be reached. Make sure an LLM API key is configured in the backend .env and try again.]"

    def _is_transient(self, message: str) -> bool:
        low = message.lower()
        return "503" in low or "429" in low or "unavailable" in low or "high demand" in low

    @staticmethod
    def _friendly_fallback(chunk: str) -> str:
        """Turn the internal sentinel into a human-friendly message."""
        if chunk.startswith("__FALLBACK__"):
            return (
                "\n\nThe AI model is temporarily unavailable (it has hit its rate limit). "
                "Please wait about a minute and then try asking again."
            )
        return chunk

    def _generate_gemini(self, prompt: str):
        import time

        last_error = None
        for attempt in range(3):
            try:
                response = self._gemini_client.models.generate_content(
                    model=self.model_name,
                    contents=prompt,
                    config={"max_output_tokens": 1200, "temperature": 0.3},
                )
                yield response.text or ""
                return
            except Exception as e:
                last_error = e
                msg = str(e)
                if self._is_transient(msg) and attempt < 2:
                    print(f"Gemini transient error ({msg[:60]}), retrying {attempt + 1}/3")
                    time.sleep(2 * (attempt + 1))
                    continue
                break
        # Gemini unavailable -> signal the caller to fall back to HF/OpenRouter
        # so users never see a raw provider error as their answer.
        last_msg = str(last_error)
        if self._is_transient(last_msg):
            yield "__FALLBACK__"
            return
        print(f"Gemini LLM Error: {last_msg}")
        yield "__FALLBACK__"

    def _generate_ollama(self, prompt: str):
        messages = [
            {
                "role": "system",
                "content": (
                    "You are Waflo, an advanced AI assistant. Answer the user's "
                    "query in a clear, helpful, conversational way exactly like a "
                    "general-purpose chatbot (e.g., ChatGPT)."
                ),
            },
            {"role": "user", "content": prompt},
        ]
        stream = self._ollama_client.chat.completions.create(
            model=self._ollama_model,
            messages=messages,
            stream=True,
        )
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

    def _generate_openrouter(self, prompt: str):
        messages = [
            {
                "role": "system",
                "content": (
                    "You are Waflo, an advanced AI assistant. Answer the user's "
                    "query in a clear, helpful, conversational way exactly like a "
                    "general-purpose chatbot (e.g., ChatGPT)."
                ),
            },
            {"role": "user", "content": prompt},
        ]
        stream = self._openrouter_client.chat.completions.create(
            model=self._openrouter_model,
            messages=messages,
            max_tokens=1200,
            temperature=0.3,
            stream=True,
            extra_headers={
                "HTTP-Referer": "http://127.0.0.1:8000",
                "X-Title": "Waflo",
            },
        )
        total = 0
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                total += len(chunk.choices[0].delta.content)
                yield chunk.choices[0].delta.content
        # An empty (e.g. no-credit) OpenRouter response would otherwise end the
        # conversation silently; surface it so the higher-level fallback runs.
        if total == 0:
            raise RuntimeError("OpenRouter returned an empty completion")

    def _generate_hf(self, prompt: str):
        try:
            messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
            response_stream = self._hf_client.chat_completion(
                model=self._hf_model,
                messages=messages,
                max_tokens=1024,
                stream=True,
            )
            for chunk in response_stream:
                if chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
        except Exception as e:
            print(f"Hugging Face Error: {e}")
            yield f"\n\n[Hugging Face Error: {str(e)}. Please check your HF_TOKEN.]"
