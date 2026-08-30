from dotenv import load_dotenv
from pydantic_settings import BaseSettings

load_dotenv()


class Settings(BaseSettings):
    # Hugging Face API
    HF_TOKEN: str = ""

    # Tavily Web Search API
    TAVILY_API_KEY: str = ""

    # Supabase Configuration (for authentication & rate limiting)
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""  # Anonymous key for client
    SUPABASE_SERVICE_ROLE_KEY: str = ""  # Service role key for backend (KEEP SECRET)

    # Browser Use API (for AI Agentic Commerce)
    BROWSER_USE_API_KEY: str = ""

    # LLM providers
    GEMINI_API_KEY: str = ""
    GROQ_API_KEY: str = ""
    OPENROUTER_API_KEY: str = ""

    # Razorpay (test mode for the AI commerce checkout)
    # Get test keys from: https://dashboard.razorpay.com/app/keys (Test Mode)
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    RAZORPAY_WEBHOOK_SECRET: str = ""

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "allow",
    }