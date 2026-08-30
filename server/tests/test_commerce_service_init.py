import os

from config import Settings


def test_settings_accepts_cloud_provider_keys():
    settings = Settings(
        GROQ_API_KEY='gsk_test',
        GEMINI_API_KEY='gemini_test',
        BROWSER_USE_API_KEY='bu_test',
    )

    assert settings.GROQ_API_KEY == 'gsk_test'
    assert settings.GEMINI_API_KEY == 'gemini_test'
    assert settings.BROWSER_USE_API_KEY == 'bu_test'
