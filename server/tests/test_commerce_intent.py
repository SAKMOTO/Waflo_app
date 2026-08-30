"""Regression tests for intent parsing in _analyze_user_intent.

The exact demo query must resolve to:
    product_type = "mechanical keyboard"
    max_budget   = 5000
    use_case     = "programming"

Guards the 'under 5000 rs' budget phrasing and the noun-phrase product type
(not the raw first word "find"). Each instantiation prints Gemini-init logs;
these are expected and harmless.
"""

from services.commerce_agent_service import CommerceAgentService

svc = CommerceAgentService()


def test_demo_query_intent():
    intent = svc._analyze_user_intent("find a mechanical keyboard under 5000 rs for programming")
    assert intent["product_type"] == "mechanical keyboard"
    assert intent["max_budget"] == 5000
    assert intent["use_case"] == "programming"


def test_budget_rs_after_number():
    intent = svc._analyze_user_intent("gaming mouse under rs 2000")
    assert intent["max_budget"] == 2000


def test_budget_symbol_inline():
    intent = svc._analyze_user_intent("headphones under ₹3000")
    assert intent["max_budget"] == 3000


def test_budget_below_without_symbol():
    intent = svc._analyze_user_intent("laptops below 45000")
    assert intent["max_budget"] == 45000


def test_product_type_skips_leading_verb():
    intent = svc._analyze_user_intent("find a wireless keyboard for office")
    assert intent["product_type"] == "wireless keyboard"
    assert intent["use_case"] == "office"
    assert intent["max_budget"] is None


def test_product_type_usage_case_still_detected():
    intent = svc._analyze_user_intent("find a gaming mouse under rs 2000 for gaming")
    assert intent["product_type"] == "gaming mouse"
    assert intent["max_budget"] == 2000
    assert intent["use_case"] == "gaming"