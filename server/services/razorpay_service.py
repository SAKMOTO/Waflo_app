"""Razorpay payment integration (Test Mode) for the Waflo AI commerce agent.

Design notes
------------
Money actions are *bounded and gated*: this module only creates a Razorpay order
and verifies a payment. It never charges or auto-pays on the agent's behalf. The
caller is responsible for the explicit user-approval gate before creating an order.

If no Razorpay keys are configured, the service transparently runs in "demo mode":
it returns a simulated Razorpay order id and a deterministic success only when a
valid demo payment id is supplied. This lets the full merchant->checkout flow be
demonstrated end-to-end without a live account, while real credentials switch it
to the actual Razorpay Orders API automatically (still in test mode).
"""

import hashlib
import hmac
import logging
from typing import Dict, Optional
from uuid import uuid4

import requests

from config import Settings
from pydantic_models.commerce_models import Order, OrderStatus

logger = logging.getLogger(__name__)

RAZORPAY_ORDERS_URL = "https://api.razorpay.com/v1/orders"

# Demo-mode test cards usually used in Razorpay's dashboard test suite.
DEMO_PAYMENT_TOKENS = {
    "pay_demo_success": OrderStatus.PAID,
    "pay_demo_fail": OrderStatus.FAILED,
}


class RazorpayServiceError(Exception):
    """Raised when a Razorpay API call fails (not a payment failure)."""


class RazorpayService:
    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self.key_id = (self.settings.RAZORPAY_KEY_ID or "").strip()
        self.key_secret = (self.settings.RAZORPAY_KEY_SECRET or "").strip()
        self.webhook_secret = (self.settings.RAZORPAY_WEBHOOK_SECRET or "").strip()
        # In-memory store of orders created through this service instance.
        self._orders: Dict[str, Order] = {}

    # ---------------------------------------------------------------- helpers

    @property
    def configured(self) -> bool:
        """True when real Razorpay credentials are present."""
        return bool(self.key_id and self.key_secret)

    @property
    def test_mode(self) -> bool:
        # When real keys are present we still call the live API but users should
        # have their dashboard in Test Mode. If no keys, we use demo mode.
        return not self.configured

    def _auth(self):
        return (self.key_id, self.key_secret)

    # ---------------------------------------------------------------- orders API

    def create_order(self, order: Order) -> Order:
        """Create a Razorpay order for an already-approved Order object.

        Returns the same Order with ``razorpay_order_id`` populated.
        Raises RazorpayServiceError on API failure.
        """
        if order.status != OrderStatus.APPROVED:
            raise RazorpayServiceError(
                "Order must be APPROVED (user approval gate) before creating a Razorpay order."
            )

        amount_paise = int(round(order.amount * 100))

        if not self.configured:
            # ---- demo mode ----
            demo_order_id = f"order_{uuid4().hex[:14]}"
            order.razorpay_order_id = demo_order_id
            order.metadata["mode"] = "demo"
            logger.info(f"[razorpay] demo order created: {demo_order_id} for ₹{order.amount}")
            self._orders[order.order_id] = order
            return order

        # ---- real API ----
        payload = {
            "amount": amount_paise,
            "currency": order.currency,
            "receipt": order.receipt or f"waflo_{order.task_id[-8:]}",
            "notes": {
                "task_id": order.task_id,
                "waflo_order_id": order.order_id,
            },
        }
        try:
            resp = requests.post(
                RAZORPAY_ORDERS_URL,
                json=payload,
                auth=self._auth(),
                timeout=15,
            )
        except requests.RequestException as e:
            raise RazorpayServiceError(f"Razorpay network error creating order: {e}") from e

        if resp.status_code not in (200, 201):
            raise RazorpayServiceError(
                f"Razorpay create order failed [{resp.status_code}]: {resp.text[:500]}"
            )

        data = resp.json()
        order.razorpay_order_id = data.get("id")
        order.metadata["mode"] = "live"
        self._orders[order.order_id] = order
        logger.info(f"[razorpay] order created: {order.razorpay_order_id} for ₹{order.amount}")
        return order

    def get_order(self, razorpay_order_id: str) -> Optional[Dict]:
        """Fetch a Razorpay order's current status."""
        if not self.configured:
            for o in self._orders.values():
                if o.razorpay_order_id == razorpay_order_id:
                    return {
                        "id": razorpay_order_id,
                        "amount": int(o.amount * 100),
                        "currency": o.currency,
                        "status": o.status.value,
                    }
            return None
        try:
            resp = requests.get(
                f"{RAZORPAY_ORDERS_URL}/{razorpay_order_id}",
                auth=self._auth(),
                timeout=15,
            )
        except requests.RequestException as e:
            raise RazorpayServiceError(f"Razorpay network error fetching order: {e}") from e
        if resp.status_code != 200:
            raise RazorpayServiceError(
                f"Razorpay fetch order failed [{resp.status_code}]: {resp.text[:500]}"
            )
        return resp.json()

    # ---------------------------------------------------------------- verification

    def verify_payment_signature(
        self,
        razorpay_order_id: str,
        razorpay_payment_id: str,
        razorpay_signature: Optional[str] = None,
    ) -> bool:
        """Verify a Razorpay payment signature (either from checkout SDK or webhook).

        In demo mode the signature is not required.
        """
        # demo mode: accept known demo payment tokens
        if not self.configured:
            return razorpay_payment_id in DEMO_PAYMENT_TOKENS

        if not razorpay_signature:
            return False
        payload = f"{razorpay_order_id}|{razorpay_payment_id}"
        expected = hmac.new(
            self.key_secret.encode("utf-8"),
            payload.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, razorpay_signature)

    def verify_webhook_signature(
        self, raw_body: bytes, received_signature: Optional[str]
    ) -> bool:
        """Verify the Razorpay webhook X-Razorpay-Signature using the webhook secret."""
        if not self.webhook_secret or not received_signature:
            # Without a configured webhook secret we cannot cryptographically verify.
            logger.warning(
                "[razorpay] webhook secret not configured; skipping signature verification"
            )
            return False
        expected = hmac.new(
            self.webhook_secret.encode("utf-8"),
            raw_body,
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, received_signature)

    def resolve_payment_status(
        self,
        order: Order,
        razorpay_payment_id: str,
        razorpay_signature: Optional[str] = None,
    ) -> OrderStatus:
        """Resolve the final payment status for an order given a payment id.

        demo mode: success if the payment token maps to PAID, else FAILED.
        live mode: verify the signature; a valid signature implies paid.
        """
        if not self.configured:
            return DEMO_PAYMENT_TOKENS.get(razorpay_payment_id, OrderStatus.FAILED)

        valid = self.verify_payment_signature(
            order.razorpay_order_id or "",
            razorpay_payment_id,
            razorpay_signature,
        )
        return OrderStatus.PAID if valid else OrderStatus.FAILED
