"""Waflo Merchant Catalog.

A small, deterministic, locally-stored merchant catalog so the AI commerce agent
has a reliable source of products for the Razorpay checkout demo, independent of
the (sometimes flaky) live browser scraping. The catalog is what lets the agent
demonstrate a full merchant transaction end-to-end.

The agent can still enrich results from live browsing, but catalog products are
the ones it can actually put through the Razorpay test checkout.
"""

import logging
from typing import List, Optional

from config import Settings
from pydantic_models.commerce_models import MerchantProduct

logger = logging.getLogger(__name__)


class MerchantCatalogService:
    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self._products: List[MerchantProduct] = self._seed_catalog()

    @staticmethod
    def _seed_catalog() -> List[MerchantProduct]:
        return [
            MerchantProduct(
                id="KB001",
                name="Waflo Mechanical Keyboard Pro",
                price=4499.0,
                category="keyboard",
                description="Hot-swappable mechanical keyboard built for fast, accurate typing.",
                features=[
                    "Mechanical switches (red)",
                    "Hot-swappable",
                    "RGB backlight",
                    "USB-C + Bluetooth",
                    "Anti-ghosting",
                ],
                rating=4.6,
                stock=23,
                tags=["keyboard", "mechanical", "typing", "programming", "wireless"],
            ),
            MerchantProduct(
                id="KB002",
                name="Waflo TKL Compact Keyboard",
                price=2999.0,
                category="keyboard",
                description="Tenkeyless compact mechanical keyboard for tidy desks and fast typing.",
                features=[
                    "TKL layout",
                    "Mechanical brown switches",
                    "Aluminium top plate",
                    "USB-C wired",
                ],
                rating=4.3,
                stock=41,
                tags=["keyboard", "mechanical", "compact", "typing"],
            ),
            MerchantProduct(
                id="KB003",
                name="Waflo Silicone Membrane Keyboard",
                price=799.0,
                category="keyboard",
                description="Budget-friendly quiet membrane keyboard for everyday use.",
                features=[
                    "Quiet membrane keys",
                    "Multimedia keys",
                    "USB wired",
                ],
                rating=3.9,
                stock=120,
                tags=["keyboard", "membrane", "budget"],
            ),
            MerchantProduct(
                id="MS001",
                name="Waflo Precision Gaming Mouse",
                price=1299.0,
                category="mouse",
                description="High-DPI gaming mouse with programmable buttons.",
                features=[
                    "16000 DPI sensor",
                    "RGB lighting",
                    "Programmable buttons",
                    "Wired USB",
                ],
                rating=4.4,
                stock=67,
                tags=["mouse", "gaming", "precision"],
            ),
            MerchantProduct(
                id="HP001",
                name="Waflo Wireless Headphones",
                price=2999.0,
                category="headphones",
                description="Over-ear wireless headphones with active noise cancellation.",
                features=[
                    "Active noise cancellation",
                    "Bluetooth 5.3",
                    "30h battery",
                    "Built-in mic",
                ],
                rating=4.5,
                stock=35,
                tags=["headphones", "wireless", "anc"],
            ),
            MerchantProduct(
                id="HP002",
                name="Waflo Earbuds Lite",
                price=999.0,
                category="headphones",
                description="Lightweight true-wireless earbuds for everyday listening.",
                features=[
                    "True wireless",
                    "Touch controls",
                    "Bluetooth 5.0",
                    "IPX4 splash resistant",
                ],
                rating=4.0,
                stock=88,
                tags=["headphones", "earbuds", "wireless"],
            ),
        ]

    def list_products(self) -> List[MerchantProduct]:
        return list(self._products)

    def get_product(self, product_id: str) -> Optional[MerchantProduct]:
        for p in self._products:
            if p.id == product_id:
                return p
        return None

    def search(self, query: str = "", category: Optional[str] = None) -> List[MerchantProduct]:
        """Case-insensitive keyword + category search over the catalog."""
        q = (query or "").lower().strip()
        results: List[MerchantProduct] = []
        for p in self._products:
            if category and p.category != category:
                continue
            if not q:
                results.append(p)
                continue
            haystack = " ".join([p.name, p.description, p.category] + p.features + p.tags).lower()
            tokens = q.split()
            if all(tok in haystack for tok in tokens):
                results.append(p)
        return results
