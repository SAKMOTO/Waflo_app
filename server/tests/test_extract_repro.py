"""Regression tests for the commerce agent product extractor.

The browser-use agent reports products as markdown like:

    1. **Kreo Swarm 65 (Flipkart)**
       - **Price:** ₹4,199

The product name lives on the line ABOVE the `**Price:** ₹X` label. The old
parser kept only the current line before the price, resolved the name to
"price" (a junk token), and dropped every product -> FinalResultEvent had
zero recommendations and the Flutter UI showed no product cards.

These tests lock the fixed behaviour in so it does not regress.
"""

from services.commerce_agent_service import CommerceAgentService

svc = CommerceAgentService()
extract = svc._extract_structured_products


def pairs(text):
    return [(p.name, p.price) for p in extract(text)]


FINAL_RESULT_MARKDOWN = """
I have completed the search for mechanical keyboards under 5000 INR.

### Summary of Findings:
- **Total products found:** 3

### Top 3 Recommendations:
1. **Kreo Swarm 65 (Flipkart)**
   - **Price:** ₹4,199
   - **Key Features:** Wireless, Wired USB, Bluetooth, 5-Layer Sound Dampening.

2. **Cosmic Byte CB-GK-43 Phantom TKL (Amazon)**
   - **Price:** ₹2,999
   - **Key Features:** TKL Layout, Mechanical switches.

3. **EvoFox Katana S Mini (Amazon)**
   - **Price:** ₹2,499 (approx)
   - **Key Features:** Hot-swappable switches, Anti-Ghosting.
"""


def test_markdown_labeled_products_extract_name_above_price():
    result = pairs(FINAL_RESULT_MARKDOWN)
    assert ("Kreo Swarm 65", 4199.0) in result
    assert ("Cosmic Byte CB-GK-43 Phantom TKL", 2999.0) in result
    assert ("EvoFox Katana S Mini", 2499.0) in result


def test_plain_labeled_products():
    text = "Kreo Swarm 65\n- Price: ₹4,199\nCosmic Byte\nPrice ₹2,999"
    result = pairs(text)
    assert ("Kreo Swarm 65", 4199.0) in result
    assert ("Cosmic Byte", 2999.0) in result


def test_strikethrough_price_is_skipped_and_lower_now_price_kept():
    text = "1. **Kreo Swarm 65** - ~~₹7,999~~ Now ₹4,199"
    result = pairs(text)
    assert result == [("Kreo Swarm 65", 4199.0)]


def test_table_rows():
    text = "| Name | Price |\n|------|-------|\n| Redragon K673 Pro | ₹3,499 |\n| Kreo Swarm 65 | ₹4,199 |"
    result = pairs(text)
    assert ("Redragon K673 Pro", 3499.0) in result
    assert ("Kreo Swarm 65", 4199.0) in result


def test_prose_without_prices_yields_nothing():
    text = ("I have identified several potential keyboards under 5000 INR: Redragon K673 Pro, "
            "Kreo Swarm 65. Extracted details for 'Kreo Swarm 65'. Now saving to results.md.")
    assert pairs(text) == []


def test_budget_and_range_noise_is_rejected():
    text = ("Price Range:** Most options fall between **₹2,000 - ₹3,000**.\n"
            "Found a good deal under ₹2,500 for the Vissles.")
    assert pairs(text) == []


def test_trailing_jargon_is_stripped_from_names():
    text = "EvoFox Katana S Mini at price ₹1,599\nRedragon K673 Pro costs ₹3,499 only."
    result = pairs(text)
    assert ("EvoFox Katana S Mini", 1599.0) in result
    assert ("Redragon K673 Pro", 3499.0) in result


def test_source_site_annotation_stripped_from_name():
    result = pairs("1. **Kreo Swarm 65 (Flipkart)**\n   - **Price:** ₹4,199")
    assert result == [("Kreo Swarm 65", 4199.0)]