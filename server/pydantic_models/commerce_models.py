from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List, Dict
from datetime import datetime
from enum import Enum


class AgentStatus(str, Enum):
    """Agent status states"""
    STARTING = "starting"
    ANALYZING = "analyzing"
    PLANNING = "planning"
    BROWSING = "browsing"
    EXTRACTING = "extracting"
    COMPARING = "comparing"
    RECOMMENDING = "recommending"
    COMPLETED = "completed"
    ERROR = "error"
    CANCELLED = "cancelled"


class CommerceEventType(str, Enum):
    """Types of commerce events"""
    AGENT_STATUS = "agent_status"
    BROWSER_ACTION = "browser_action"
    PRODUCT_FOUND = "product_found"
    FINAL_RESULT = "final_result"
    ERROR = "error"
    CANCELLED = "cancelled"
    CONFIRMATION_REQUIRED = "confirmation_required"
    SELECTION_CONFIRMED = "selection_confirmed"
    COMPARISON = "comparison"
    GROWTH_RESULT = "growth_result"
    # Payment / checkout events
    CHECKOUT_READY = "checkout_ready"
    CHECKOUT_BLOCKED = "checkout_blocked"
    ORDER_CREATED = "order_created"
    PAYMENT_INITIATED = "payment_initiated"
    PAYMENT_SUCCESS = "payment_success"
    PAYMENT_FAILED = "payment_failed"


class ProductInfo(BaseModel):
    """Live product information extracted from browser"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    name: str
    price: Optional[float] = None
    features: List[str] = []
    rating: Optional[str] = None
    availability: Optional[str] = None
    source_url: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class Recommendation(BaseModel):
    """Product recommendation with reasoning"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    product: ProductInfo
    score: float
    reasoning: List[str]
    matches_budget: bool
    matches_requirements: bool


class AgentStatusEvent(BaseModel):
    """Agent status update event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.AGENT_STATUS
    status: AgentStatus
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class BrowserActionEvent(BaseModel):
    """Browser action event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.BROWSER_ACTION
    action: str
    message: str
    url: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ProductFoundEvent(BaseModel):
    """Product found event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.PRODUCT_FOUND
    product: ProductInfo
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class FinalResultEvent(BaseModel):
    """Final result event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.FINAL_RESULT
    recommendations: List[Recommendation]
    total_products_analyzed: int
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ErrorEvent(BaseModel):
    """Error event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.ERROR
    message: str
    error_type: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class CancelledEvent(BaseModel):
    """Cancellation event"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    type: CommerceEventType = CommerceEventType.CANCELLED
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class CommerceAgentRequest(BaseModel):
    """Request to start commerce agent"""
    query: str
    max_budget: Optional[float] = None
    use_case: Optional[str] = None
    requirements: List[str] = []


class AuditLogEntry(BaseModel):
    """Audit trail entry"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})
    
    task_id: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    event_type: str
    action: str
    status: str
    message: str
    metadata: dict = {}


class ProductComparisonLine(BaseModel):
    """A single attribute comparison across products"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    attribute: str
    values: List[str] = Field(default_factory=list)


class ComparisonEvent(BaseModel):
    """Event carrying a side-by-side product comparison (real extracted data only)"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.COMPARISON
    compared_products: List[ProductInfo]
    comparison_lines: List[ProductComparisonLine] = Field(default_factory=list)
    verdict: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ConfirmationRequiredEvent(BaseModel):
    """Event requesting explicit user confirmation before a bounded commerce action"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.CONFIRMATION_REQUIRED
    product: ProductInfo
    action_description: str
    requires_confirmation: bool = True
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class SelectionConfirmedEvent(BaseModel):
    """Event confirming the user's explicit selection + confirmation"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.SELECTION_CONFIRMED
    product: ProductInfo
    note: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class GrowthResultEvent(BaseModel):
    """Event carrying results of a growth action (cross-sell / upsell / similar)"""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.GROWTH_RESULT
    growth_type: str  # cross_sell | upsell | similar
    triggered_by: ProductInfo
    products: List[ProductInfo] = Field(default_factory=list)
    message: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ---------------------------------------------------------------------------
# Phase 4 — Merchant catalog, orders and Razorpay test checkout
# ---------------------------------------------------------------------------


class MerchantProduct(BaseModel):
    """A product in the Waflo merchant catalog (deterministic local data)."""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    id: str
    name: str
    price: float
    currency: str = "INR"
    category: str
    description: str = ""
    features: List[str] = Field(default_factory=list)
    rating: Optional[float] = None
    stock: int = 0
    image_url: Optional[str] = None
    tags: List[str] = Field(default_factory=list)

    def to_product_info(self, source_url: str = "waflo-merchant") -> ProductInfo:
        """Convert into a ProductInfo so the merchant catalog plugs into the
        existing recommendation / comparison engine."""
        return ProductInfo(
            name=self.name,
            price=self.price,
            features=list(self.features),
            rating=(f"{self.rating}/5" if self.rating is not None else None),
            availability="In Stock" if self.stock > 0 else "Out of Stock",
            source_url=source_url,
        )


class OrderStatus(str, Enum):
    PENDING = "pending"          # cart / awaiting user approval
    APPROVED = "approved"        # user approved, order object created
    PAID = "paid"                # payment confirmed
    FAILED = "failed"            # payment failed / rejected
    CANCELLED = "cancelled"      # user cancelled before payment


class OrderItem(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    product_id: str
    name: str
    quantity: int = 1
    unit_price: float
    currency: str = "INR"


class Order(BaseModel):
    """An order created by the AI commerce agent (money action is gated)."""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    order_id: str
    task_id: str
    items: List[OrderItem] = Field(default_factory=list)
    amount: float
    currency: str = "INR"
    status: OrderStatus = OrderStatus.PENDING
    razorpay_order_id: Optional[str] = None
    razorpay_payment_id: Optional[str] = None
    receipt: Optional[str] = None
    approval_required: bool = True
    approval_granted: bool = False
    reason: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    metadata: Dict = Field(default_factory=dict)


class CheckoutReadyEvent(BaseModel):
    """Sent to the client when the agent is ready to create an order for a product.
    This is the single approval gate before any money/bounded action."""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.CHECKOUT_READY
    product: ProductInfo
    amount: float
    currency: str = "INR"
    action_description: str
    requires_confirmation: bool = True
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class CheckoutBlockedEvent(BaseModel):
    """Sent when a requested purchase violates a user-defined policy constraint
    (e.g. a budget cap). No order and no payment is ever created."""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.CHECKOUT_BLOCKED
    product: ProductInfo
    amount: float
    currency: str = "INR"
    max_budget: Optional[float] = None
    reason: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class OrderCreatedEvent(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.ORDER_CREATED
    order: Order
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class PaymentInitiatedEvent(BaseModel):
    """Razorpay order created; client should render the checkout (test mode).
    Contains the checkout/order ids the client needs to launch payment."""
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.PAYMENT_INITIATED
    order_id: str
    razorpay_order_id: Optional[str] = None
    amount: float
    currency: str = "INR"
    key_id: Optional[str] = None
    merchant_name: str = "Waflo Merchant"
    test_mode: bool = True
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class PaymentSuccessEvent(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.PAYMENT_SUCCESS
    order_id: str
    razorpay_payment_id: Optional[str] = None
    amount: float
    currency: str = "INR"
    message: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class PaymentFailedEvent(BaseModel):
    model_config = ConfigDict(json_encoders={datetime: lambda v: v.isoformat()})

    task_id: str
    type: CommerceEventType = CommerceEventType.PAYMENT_FAILED
    order_id: str
    amount: float
    currency: str = "INR"
    reason: Optional[str] = None
    recovered: bool = False
    timestamp: datetime = Field(default_factory=datetime.utcnow)