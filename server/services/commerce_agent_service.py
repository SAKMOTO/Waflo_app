import asyncio
import logging
import os
import re
from typing import Optional, Callable, List
from datetime import datetime
from uuid import uuid4

from config import Settings
from pydantic_models.commerce_models import (
    AgentStatus,
    ProductInfo,
    Recommendation,
    AgentStatusEvent,
    BrowserActionEvent,
    ProductFoundEvent,
    FinalResultEvent,
    ErrorEvent,
    CancelledEvent,
    AuditLogEntry,
    CommerceAgentRequest,
    ComparisonEvent,
    ProductComparisonLine,
    ConfirmationRequiredEvent,
    SelectionConfirmedEvent,
    GrowthResultEvent,
    MerchantProduct,
    Order,
    OrderItem,
    OrderStatus,
    CheckoutReadyEvent,
    CheckoutBlockedEvent,
    OrderCreatedEvent,
    PaymentInitiatedEvent,
    PaymentSuccessEvent,
    PaymentFailedEvent,
)
from services.audit_service import AuditService
from services.merchant_catalog_service import MerchantCatalogService
from services.razorpay_service import RazorpayService, RazorpayServiceError
from vendor_browser_use import bootstrap_vendored_browser_use, IS_VENDORED_PRESENT

logger = logging.getLogger(__name__)


def get_settings():
    return Settings()

# Always resolve browser_use from the vendored <repo>/browser-use folder so a
# stale PyPI pin can never shadow it.
bootstrap_vendored_browser_use()

try:
    from browser_use import Agent, BrowserSession, BrowserProfile, ChatGroq, ChatGoogle
    BROWSER_USE_AVAILABLE = True
except ImportError:
    BROWSER_USE_AVAILABLE = False
    logger.warning("browser-use not imported, commerce agent will not work")


class CommerceAgentService:
    """Service for AI-powered commerce using browser-use with cloud LLM fallback support."""

    def __init__(self):
        self.active_tasks: dict[str, bool] = {}
        self.audit_logs: list[AuditLogEntry] = []
        self.audit_service = AuditService()
        self.task_data: dict[str, dict] = {}
        self.background_tasks: dict[str, asyncio.Task] = {}
        self.browser_sessions: dict[str, list] = {}
        self.llm = None
        self.merchant_catalog = MerchantCatalogService()
        self.razorpay = RazorpayService()

        if not BROWSER_USE_AVAILABLE:
            logger.error("browser-use is not available")
            return

        self._initialize_llm()

    def _initialize_llm(self):
        settings = get_settings()

        try:
            if settings.GEMINI_API_KEY:
                logger.info("Initializing Gemini API...")
                self.llm = ChatGoogle(
                    model='gemini-3.1-flash-lite',
                    api_key=settings.GEMINI_API_KEY,
                    temperature=0.0,
                )
                logger.info("✅ Gemini API initialized successfully!")
                return

            if settings.GROQ_API_KEY:
                logger.info("Initializing Groq API...")
                self.llm = ChatGroq(
                    model='openai/gpt-oss-120b',
                    api_key=settings.GROQ_API_KEY,
                    temperature=0.0,
                )
                logger.info("✅ Groq API initialized successfully!")
                return

            logger.warning("No LLM provider key configured. Commerce agent will be unavailable until a provider key is set in the environment.")
            self.llm = None

        except Exception as e:
            logger.error(f"❌ Failed to initialize cloud LLM: {e}")
            self.llm = None

    def _create_browser_session(self, task_id: str):
        settings = get_settings()
        allowed_domains = [
            'google.com',
            'www.google.com',
            'www.amazon.in',
            'amazon.in',
            'flipkart.com',
            'www.flipkart.com',
            'myntra.com',
            'www.myntra.com',
            'www.reliancedigital.in',
            'reliancedigital.in',
            'www.croma.com',
            'croma.com',
        ]

        # Do NOT force headless=True/False here: browser-use auto-detects
        # (visible browser on a machine with a display, headless otherwise),
        # so the demo shows the live browser locally yet still runs on a
        # headless judge server. BROWSER_USE_HEADLESS can force it either way.
        browser_profile = BrowserProfile(
            headless=os.getenv('BROWSER_USE_HEADLESS', '') or None,
            allowed_domains=allowed_domains,
            minimum_wait_page_load_time=0.2,
            wait_between_actions=0.2,
            keep_alive=False,
        )

        return BrowserSession(
            browser_profile=browser_profile,
            allowed_domains=allowed_domains,
            keep_alive=False,
            user_data_dir=None,
            use_cloud=False,
        )
    
    def _add_audit_log(self, task_id: str, event_type: str, action: str, 
                      status: str, message: str, metadata: dict = None):
        """Add entry to audit trail"""
        log_entry = AuditLogEntry(
            task_id=task_id,
            event_type=event_type,
            action=action,
            status=status,
            message=message,
            metadata=metadata or {}
        )
        self.audit_logs.append(log_entry)
        self.audit_service.save_audit_log(log_entry)
        logger.info(f"[AUDIT] {task_id}: {action} - {message}")
    
    def _json_safe(self, value):
        """Recursively convert non-JSON-serializable values (e.g. datetime) to JSON-safe ones."""
        if isinstance(value, dict):
            return {k: self._json_safe(v) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [self._json_safe(v) for v in value]
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        return str(value)

    async def _send_event(self, event_callback: Callable, event_data: dict):
        """Send event to Flutter via callback."""
        try:
            if event_callback:
                payload = event_data
                if hasattr(payload, 'model_dump'):
                    payload = payload.model_dump(mode='json', exclude_none=True)
                if isinstance(payload, dict):
                    payload = {k: v for k, v in payload.items() if v is not None}
                # Ensure datetime and any other non-serializable objects become JSON-safe.
                payload = self._json_safe(payload)
                await event_callback(payload)
        except Exception as e:
            logger.error(f"Failed to send event: {e}")
    
    def _extract_products_from_history(self, history_text: str) -> List[ProductInfo]:
        """Extract product information from agent history"""
        products = []
        
        # Look for product patterns in the text
        lines = history_text.split('\n')
        current_product = None
        
        for line in lines:
            line = line.strip()
            
            # Detect product lines (common patterns)
            if any(keyword in line.lower() for keyword in ['product', 'item', 'name:', 'price:', '₹', '$']):
                if current_product and current_product.name:
                    products.append(current_product)
                
                # Extract name
                name_match = re.search(r'(?:product|item|name)[:\s]+(.+?)(?:\||$|price)', line, re.IGNORECASE)
                if name_match:
                    name = name_match.group(1).strip()
                    if name and len(name) > 3:
                        current_product = ProductInfo(name=name, source_url="browser_search")
                        continue
            
            if current_product:
                # Extract price
                price_match = re.search(r'[₹$]\s*[\d,]+\.?\d*', line)
                if price_match and not current_product.price:
                    try:
                        price_str = price_match.group().replace('₹', '').replace('$', '').replace(',', '').strip()
                        current_product.price = float(price_str)
                    except ValueError:
                        pass
                
                # Extract features
                feature_keywords = ['battery', 'wireless', 'bluetooth', 'noise', 'cancel', 'hours', 'mah', 'gb', 'inch']
                for keyword in feature_keywords:
                    if keyword.lower() in line.lower() and len(current_product.features) < 5:
                        if line not in current_product.features:
                            current_product.features.append(line.strip())
                
                # Extract rating
                rating_match = re.search(r'(\d\.?\d*)\s*\/\s*5|\d\.?\d*\s*stars?', line, re.IGNORECASE)
                if rating_match and not current_product.rating:
                    current_product.rating = rating_match.group()
                
                # Extract availability
                if 'in stock' in line.lower():
                    current_product.availability = "In Stock"
                elif 'out of stock' in line.lower():
                    current_product.availability = "Out of Stock"
        
        if current_product and current_product.name:
            products.append(current_product)
        
        return products
    
    _PRODUCT_PRICE_RE = re.compile(
        r'(?:[₹$]|rs\.?\s*|inr\s*)\s*~?\s*([\d][\d,]*(?:\.\d+)?)',
        re.IGNORECASE,
    )
    _BAD_PRODUCT_NAMES = {
        'price', 'rs', 'inr', 'item', 'product', 'product name', 'key features',
        'key', 'features', 'rating', 'available',
    }

    # Fragments/UI-noise that are NOT product names (prose, price-range labels,
    # deal banners, chart text). Kept as a regex so real product names pass.
    _NOISE_NAME_RE = re.compile(
        r'(price range|most options|fall between|clicked a|up to\b|more results|'
        r'sponsored|advertisement|results? for|related to|people also|top picks|'
        r'filter|sort by|sort by|showing \d|view all|no results)', re.IGNORECASE,
    )

    def _extract_structured_products(self, history_text: str) -> List[ProductInfo]:
        """Robustly extract {name, price} pairs from agent output.

        The legacy _extract_products_from_history is too brittle for the formats the
        agent actually produces (parenthesized prices, 'Rs', '~', markdown bold,
        prices inline in memory strings). This parser scans every price marker and
        binds the text immediately before it as the product name, de-duplicating on
        (lowercased name, price).

        Hardening for real agent text:
          - skips budget qualifiers ("under Rs 3000"),
          - skips strike/label prices ("Original Price: ₹7999", "(MRP ₹7999)"),
          - strips list numbering ("1. **"), markdown (**/##), bullets,
          - keeps the LOWEST price ever seen for the same product name so an
            "Original ₹7999 / Now ₹4199" pair maps to ₹4199.
        """
        # tokens that mean the price right after them is a label/strike, not the price
        label_prefix_re = re.compile(
            r'(?:original|strike|strikethrough|mrp|msrp|list|was|before|actual)\s*price',
            re.IGNORECASE,
        )
        products: List[ProductInfo] = []
        seen: dict = {}  # name(lower) -> ProductInfo  (keeps lowest price)
        for m in self._PRODUCT_PRICE_RE.finditer(history_text):
            try:
                price = float(m.group(1).replace(',', ''))
            except ValueError:
                continue
            if price <= 0:
                continue
            start = max(0, m.start() - 120)
            before = history_text[start:m.start()]

            # 1) Skip if the price is a strike-through / "original" label price.
            trailing_label = before[-40:]
            if label_prefix_re.search(trailing_label):
                continue

            # 1.5) Skip markdown-strikethrough prices "~~₹7,999~~": those are
            # strike labels, not the live price (the real one usually follows
            # "Now ₹X"). Catching it here also avoids a duplicated noisy name.
            if (re.search(r'~{2,}\s*$', before[-16:])
                    and re.search(r'^\s*~{2,}', history_text[m.end():m.end() + 16])):
                continue

            # 2) Skip budget-cap qualifiers (word immediately before the price).
            last_words = re.split(r'[\s,;(){}|*#~=\-–—]+', before.strip())
            last_word = (last_words[-1] or '').lower() if last_words else ''
            if last_word in {
                'under', 'below', 'within', 'budget', 'than', 'upto', 'up',
                'limit', 'max', 'around', 'approximately', 'approx', 'rs', 'inr',
            }:
                continue

            # 2.1) Also skip a budget price mentioned in prose, e.g. "well within
            # the ₹5000 budget": if a budget word sits in the 40 chars before OR the
            # 12 chars after this price marker, treat it as a budget cap, not a price.
            after = history_text[m.end():m.end() + 12]
            budget_word = re.compile(
                r'(under|below|within|budget|limit|upto|around|max)', re.IGNORECASE)
            if budget_word.search(before[-40:]) or budget_word.search(after):
                continue

            # 2.5) Keep only the CURRENT line before the price (cut at the nearest
            # newline) so previous-list-line text never bleeds into the product name.
            # BUT when that line is only a bare price label ("**Price:**", "- Price:",
            # "Rs."), the real product name sits on the line ABOVE — pull it in.
            lines = before.split("\n")
            last_line = lines[-1]
            bare_label = re.search(
                r'(?:price|cost|offer|rs\.?|inr)\s*[:=~\-–—*#_`\s]*$',
                last_line, re.IGNORECASE,
            )
            if bare_label and len(lines) >= 2:
                before = lines[-2] + "\n" + last_line
            else:
                before = last_line

            # 3) Cut trailing label markers ("Price: ~", "Key Features", etc.).
            # This handles both the plain "- Price:" form and the heavily bolded
            # "**Price:**" form by finding the LAST label word before the price
            # (the one nearest the price marker) and cutting everything from it
            # onwards — the label sits right above the price, so earlier label
            # words like an availability line "In Stock" must not cut the name.
            label_matches = [
                m.start()
                for m in re.finditer(
                    r'(price|key features|rating|in stock|out of stock)',
                    before[-80:], re.IGNORECASE,
                )
            ]
            if label_matches:
                cut_pos = len(before) - len(before[-80:]) + label_matches[-1]
                before = before[:cut_pos]
            before = re.sub(r'[\s:=~\-–—*#_`]+$', '', before)
            # strip the "Original Price ₹X" context that precedes "Now ₹Y"
            before = re.sub(r'[(（]\s*(?:original|was|mrp|list|before)\s*price.*?[)）]', '', before, flags=re.IGNORECASE)

            # 4) Clean name: strip trailing junk, leading list numbering/bold/markdown.
            # NOTE: "(" / ")" are intentionally NOT stripped here so later rules can
            # recognise and drop complete parenthetical annotations like " (Flipkart)"
            # or " (₹4,199)".
            name_clean = re.sub(r'[\s,;:*#~=\-–—]+$', '', before)
            name_clean = re.sub(r'^[\s\d.\-–—*#()]+', '', name_clean)
            # drop markdown header markers and numbering like "1.", "1)", "-"
            name_clean = re.sub(r'^\s*(#+|\*+|-+|\d+[.)])\s*', '', name_clean)
            # cut off a trailing "* Price" showing a nested label
            name_clean = re.sub(r'\s*\*\*\s*price\s*$', '', name_clean, flags=re.IGNORECASE)

            # 4a) Memory prose often wraps the product, e.g.
            #   "Identified 3 products on Amazon: Kreo Swarm 65"
            #   "Extracted details for Kreo Swarm 65" / "details for Kreo Swarm 65"
            #   "found: Kreo Swarm 65" / "recommended: Cosmic Byte"
            # The real product name is the segment after the last colon, with any
            # leading verb/prep phrase ("identified", "extracted details for",
            # "found", "recommended", "product:", "on Amazon") removed.
            if ":" in name_clean:
                name_clean = name_clean.rsplit(":", 1)[-1]
            name_clean = re.sub(r'^\s*(identified|extracted details for|details for|'
                                r'found|recommended|selected|saw|sources?[:]?)\s+',
                                '', name_clean, flags=re.IGNORECASE)
            # drop a trailing parenthetical price " (₹4,199)" and any following
            # comma-joined second product "Kreo Swarm 65 (₹4,199), EvoFox ..."
            name_clean = re.sub(r'\s*\([₹$][\d,.\s~-]*\)', '', name_clean)
            name_clean = re.sub(r',\s*[A-Za-z].*$', '', name_clean)
            # collapse leftover markdown strikethrough "~~₹7,999~~" noise
            name_clean = re.sub(r'~{2,}[^~]*~{2,}', ' ', name_clean)
            # cut trailing announce-jargon: "Kreo 65 - Now ₹4199", "… at ₹1599", "… costs ₹3499"
            name_clean = re.sub(r'\s*[-–—:]\s*(?:now|today|offer)\s*$', '', name_clean, flags=re.IGNORECASE)
            name_clean = re.sub(r'\s+(?:at|for|costs?|priced\s+at|only)\s*$', '', name_clean, flags=re.IGNORECASE)

            # drop trailing source-site annotations like " (Flipkart)" / " (Amazon)"
            name_clean = re.sub(
                r'\s*[(（]\s*(?:amazon|flipkart|myntra|nykaa|snapdeal|croma|shopclues|'
                r'reliance\s*digital|reliancedigital|tatacliq|paytm|meesho|'
                r'vedant|mdcomputers|meckeys|elitehubs)[^)）]*[)）]?\s*$',
                '', name_clean, flags=re.IGNORECASE)

            # drop parenthetical duplicates like " (Original price: ₹7,999)" already removed
            name_clean = re.sub(r'\s+', ' ', name_clean).strip(' *.#[]-–—')

            if not (2 <= len(name_clean) <= 80):
                continue
            low = name_clean.lower()
            if low in self._BAD_PRODUCT_NAMES:
                continue
            # Reject prose/sentence fragments and obvious UI-noise fragments that
            # are not real product names (e.g. "Price Range:** Most options fall
            # between", "Clicked a Up To", chart/table labels). These otherwise
            # pollute the top recommendations.
            if self._NOISE_NAME_RE.search(name_clean):
                continue
            # "| Name |" table-row format: if a pipe is present, keep only the
            # text after the last table cell separator so "| Kreo Swarm 65 |" -> "Kreo Swarm 65".
            if "|" in name_clean:
                cells = [c.strip().strip('* ') for c in name_clean.split("|") if c.strip()]
                name_clean = cells[-1] if cells else name_clean
                name_clean = re.sub(r'\s{2,}', ' ', name_clean).strip(' *.#[]-–—')
                if not (2 <= len(name_clean) <= 80) or self._NOISE_NAME_RE.search(name_clean):
                    continue

            existing = seen.get(low)
            if existing is None:
                prod = ProductInfo(name=name_clean, price=price, source_url="browser_search")
                seen[low] = prod
            elif price < existing.price:  # keep lowest price for the same product
                existing.price = price
        return list(seen.values())

    
    def _analyze_user_intent(self, query: str) -> dict:
        """Analyze user query to extract shopping intent"""
        intent = {
            'product_type': None,
            'max_budget': None,
            'use_case': None,
            'requirements': []
        }
        
        budget_patterns = [
            r'₹\s*(\d+)',
            r'rs\.?\s*(\d+)\s*(?:or less|below)?',
            r'under\s*(?:₹|rs\.?)?\s*(\d+)',
            r'below\s*(?:₹|rs\.?)?\s*(\d+)',
            r'(\d+)\s*(?:₹|rs\.?)\s*(?:or less|below)',
        ]
        
        for pattern in budget_patterns:
            match = re.search(pattern, query, re.IGNORECASE)
            if match:
                try:
                    budget_value = float(match.group(1))
                    intent['max_budget'] = budget_value
                    break
                except ValueError:
                    continue
        
        use_case_keywords = [
            'college', 'office', 'gaming', 'home', 'travel', 'professional',
            'programming', 'coding', 'work', 'study', 'student',
        ]
        for keyword in use_case_keywords:
            if keyword in query.lower():
                intent['use_case'] = keyword
                break

        requirement_patterns = [
            r'with\s+(.+?)(?:,|and|for|\.$)',
            r'(?:needs?|requires?|should have)\s+(.+?)(?:,|and|for|\.$)',
        ]
        
        for pattern in requirement_patterns:
            matches = re.findall(pattern, query, re.IGNORECASE)
            for match in matches:
                if match.strip():
                    intent['requirements'].append(match.strip())
        
        intent['product_type'] = self._extract_product_type(query)

        return intent

    def _extract_product_type(self, query: str) -> Optional[str]:
        """Extract the noun phrase that names the product from a shopping query.

        Handles the demo query
            "find a mechanical keyboard under 5000 rs for programming"
        by stripping the leading shopper verb ("find"), then cutting the phrase
        at the first boundary marker (budget cap, purpose marker, currency) so it
        resolves to "mechanical keyboard" instead of the raw first word ("find").

        Falls back to the first word when no noun phrase can be isolated.
        """
        # 1) Strip leading shopper verbs / announcements.
        lead_stripped = re.sub(
            r'^\s*(?:please\s+)?(?:find|get|buy|show|search|need|want|'
            r'i\s+want(?:ed)?|looking\s+for|help\s+me\s+(?:find|get|buy)|'
            r'recommend|suggest)\s+',
            '', query, flags=re.IGNORECASE,
        )
        lead_stripped = lead_stripped.strip()

        # 2) Cut the product phrase at the first boundary marker: a budget cap
        # ("under ₹/rs 5000"), a purpose marker ("for/with programming"), or an
        # inline currency price ("₹15000"). Product names may contain digits
        # (e.g. "K68"), so only currency-marked digits cut the phrase.
        boundary = re.search(
            r'\s+(?:under|below|within|upto|up\sto|at|around|about|budget|'
            r'for|with|rs\.?|inr)\b'
            r'|\s*[₹$]\s*\d',
            lead_stripped, re.IGNORECASE,
        )
        if boundary:
            product_type = lead_stripped[:boundary.start()].strip()
        else:
            product_type = lead_stripped

        # 3) Drop articles and trailing "rs/inr/price" fillers.
        product_type = re.sub(
            r'^\s*(?:a|an|the|some)\s+', '', product_type, flags=re.IGNORECASE)
        product_type = re.sub(
            r'\s*(?:rs\.?|inr|price)\s*$', '', product_type, flags=re.IGNORECASE)

        if 2 <= len(product_type) <= 40:
            return product_type

        # 4) Fallback: first word.
        words = query.split()
        return words[0] if words else None
    
    def _score_product(self, product: ProductInfo, intent: dict) -> tuple[float, list[str]]:
        """Score a product against user intent with reasoning"""
        score = 0.0
        reasoning = []
        
        if intent.get('max_budget') and product.price:
            if product.price <= intent['max_budget']:
                score += 30
                reasoning.append(f"Matches budget (₹{product.price} ≤ ₹{intent['max_budget']})")
            else:
                reasoning.append(f"Over budget (₹{product.price} > ₹{intent['max_budget']})")
        
        if intent.get('requirements'):
            matched_features = 0
            for req in intent['requirements']:
                for feature in product.features:
                    if req.lower() in feature.lower():
                        matched_features += 1
                        reasoning.append(f"Has feature: {req}")
                        break
            
            if matched_features > 0:
                score += (matched_features / len(intent['requirements'])) * 30
        
        if intent.get('use_case'):
            for feature in product.features:
                if intent['use_case'] in feature.lower():
                    score += 20
                    reasoning.append(f"Matches {intent['use_case']} use case")
                    break
        
        if product.rating:
            try:
                rating_val = float(re.search(r'\d\.?\d*', product.rating).group())
                if rating_val >= 4.0:
                    score += 10
                    reasoning.append(f"Good rating ({product.rating})")
            except (ValueError, AttributeError):
                pass
        
        if product.availability == "In Stock":
            score += 10
            reasoning.append("Currently available")
        
        return min(score, 100), reasoning
    
    async def start_commerce_agent(
        self, 
        request: CommerceAgentRequest,
        event_callback: Optional[Callable] = None,
        task_id: Optional[str] = None
    ) -> str:
        """Start a commerce agent task using browser-use.

        If ``task_id`` is provided (e.g. pre-generated by the WebSocket handler so the
        client can cancel immediately), it is used and registered here. Otherwise a new
        one is generated. This method runs the full browser task synchronously.
        """

        if not BROWSER_USE_AVAILABLE:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id or "error",
                message="browser-use is not installed",
                error_type="ImportError"
            ).model_dump())
            raise RuntimeError("browser-use is not available")

        if not IS_VENDORED_PRESENT:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id or "error",
                message="The vendored browser-use folder (<repo>/browser-use) was not found. The shopping agent cannot start.",
                error_type="ImportError"
            ).model_dump())
            raise RuntimeError("vendored browser-use not found")

        try:
            import playwright  # noqa: F401
        except ImportError:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id or "error",
                message="Playwright is not installed in the backend environment. Run: pip install playwright && playwright install chromium",
                error_type="ImportError"
            ).model_dump())
            raise RuntimeError("playwright is not installed")
        
        if not self.llm:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id or "error",
                message="No LLM provider is configured or available. Set GEMINI_API_KEY or GROQ_API_KEY in the backend environment.",
                error_type="ConfigurationError"
            ).model_dump())
            raise RuntimeError("No LLM provider configured or available")
        
        if task_id is None:
            task_id = str(uuid4())
        self.active_tasks[task_id] = True
        self.background_tasks.setdefault(task_id, None)
        
        try:
            self._add_audit_log(task_id, "task_start", "start_commerce_agent", "started", f"Task started: {request.query}")
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.STARTING,
                message="Understanding your request..."
            ).model_dump())
            
            intent = self._analyze_user_intent(request.query)
            self._add_audit_log(task_id, "intent_analysis", "analyze_intent", "completed", f"Intent: {intent}")
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.ANALYZING,
                message=f"Analyzed request for {intent.get('product_type', 'products')}"
            ).model_dump())
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.PLANNING,
                message="Creating browser task..."
            ).model_dump())
            
            # Build comprehensive browser task
            browser_task = f"""
You are a shopping assistant. Your task is to find products based on this request: "{request.query}"

Steps to complete:
1. Go to Google (google.com)
2. Search for the product with the specified criteria
3. Visit only 2-3 shopping/commerce websites from the search results (max 3, e.g. Amazon.in, Flipkart, Myntra, Reliance Digital, Croma)
4. On those websites, open the search/category results, then CLICK INTO 2-3 individual product listing pages IN TOTAL and verify each product's details directly on its own product page (not just the category list).
5. For every individual product page you open, extract:
   - Product name (exact title)
   - Price (in ₹ or convert if needed)
   - Key features (battery life, wireless, etc.)
   - Rating (if available)
   - Availability (in stock/out of stock)
   - The product page URL

Budget constraint: {intent.get('max_budget', 'none specified')}
Requirements: {', '.join(intent.get('requirements', [])) if intent.get('requirements') else 'none specified'}

After visiting the websites and collecting product information, provide a final summary with:
- Total products found
- Top 3 recommendations with reasoning
- Comparison of key features

CRITICAL — this is verified by a judge: you MUST physically open 2-3 individual product pages (click a product in the search results and wait for its own page to load). Do NOT stop on search/category listings.
Stop early — once you have collected 2-3 confirmed products, do NOT keep opening more websites or product pages.
"""
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.BROWSING,
                message="Starting browser automation..."
            ).model_dump())
            
            browser_session = self._create_browser_session(task_id)
            self.browser_sessions.setdefault(task_id, []).append(browser_session)

            # Buffer the agent's per-step "memory" text. Unlike the brittle
            # history.extracted_content(), these memory strings reliably carry
            # the product names + prices the agent collected (see run logs).
            collected_text: list[str] = []

            async def should_stop_callback() -> bool:
                return not self.active_tasks.get(task_id, False)

            async def step_callback(state_summary, agent_output, step_number):
                """Stream granular, live browser actions to Flutter as steps happen."""
                if not self.active_tasks.get(task_id, False):
                    return
                try:
                    # Capture the model's memory/thought so a timeout or a run with
                    # empty extracted_content() never loses the products found.
                    memory = getattr(agent_output, 'memory', None)
                    if memory:
                        collected_text.append(str(memory))
                    url = getattr(state_summary, 'url', None) or ''
                    title = getattr(state_summary, 'title', None) or ''
                    next_goal = getattr(agent_output, 'next_goal', None) or ''
                    if next_goal and self._is_safe_message(next_goal, task_id):
                        await self._send_event(event_callback, BrowserActionEvent(
                            task_id=task_id,
                            action="agent_step",
                            message=next_goal,
                            url=url or None,
                        ).model_dump())
                        self._add_audit_log(task_id, "browser_step", "agent_step", "success", next_goal, {"url": url})
                except Exception as e:
                    logger.warning(f"step callback error: {e}")

            agent = Agent(
                task=browser_task,
                llm=self.llm,
                browser_session=browser_session,
                max_actions_per_step=5,
                max_failures=3,
                task_id=task_id,
                register_should_stop_callback=should_stop_callback,
                register_new_step_callback=step_callback,
            )
            
            await self._send_event(event_callback, BrowserActionEvent(
                task_id=task_id,
                action="start_browser",
                message="Browser agent initialized"
            ).model_dump())
            
            # Run the agent with timeout. 180s was too aggressive: a full run that
            # searches Google, visits 3-5 commerce sites and opens each product page
            # can need several minutes — a premature kill returned zero products to
            # Flutter. 900s bounds the demo run without cutting it short.
            timed_out = False
            try:
                history = await asyncio.wait_for(agent.run(), timeout=900)
            except asyncio.TimeoutError:
                # The browser/LLM run exceeded the bound. Do NOT discard what was
                # already collected: the Agent keeps its in-memory history even after
                # run() is cancelled, so recover the partial products and return them
                # to Flutter rather than failing the whole request.
                logger.warning(
                    f"[commerce] Agent timed out after 900 seconds for task {task_id}; "
                    "returning products collected so far (partial result)."
                )
                history = agent.history if hasattr(agent, "history") else None
                timed_out = True

            await self._send_event(event_callback, BrowserActionEvent(
                task_id=task_id,
                action="search_complete",
                message=(
                    f"Browser {'timed out; returning' if timed_out else 'completed'}. "
                    f"Visited {len(history.urls()) if history and hasattr(history, 'urls') else 0} pages"
                )
            ).model_dump())
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.EXTRACTING,
                message=f"Extracting product information...{' (partial result after timeout)' if timed_out else ''}"
            ).model_dump())
            # Extract products from EVERY captured source and combine them.
            # Using `or` here drops whichever source is non-empty — historically
            # this meant the per-step memory (which rarely carries prices) masked
            # the richer extracted_content()/final_result() where the actual
            # product names + prices live. Merging all sources fixes that.
            memory_all = "\n".join(collected_text) if collected_text else ""
            history_parts: list[str] = []
            if history:
                if hasattr(history, 'extracted_content'):
                    history_parts.extend(history.extracted_content() or [])
                # Always include the final summary too: it is the most reliable
                # source of product name + price pairs (the agent's `done` text).
                # The old `and not history_all` guard silently dropped it whenever
                # ANY extract step wrote noisy content (e.g. "info is not available"),
                # which produced zero products.
                if hasattr(history, 'final_result'):
                    try:
                        fr = history.final_result() or ""
                        if fr:
                            history_parts.append(fr)
                    except Exception:
                        pass
            history_all = "\n".join(history_parts)
            all_content = "\n".join(part for part in (memory_all, history_all) if part)
            products = self._extract_structured_products(all_content)

            # Bounded result set: users don't want a wall of products. Rank every
            # candidate by score, then keep only the top 3. The SAME short list
            # feeds both the live "found" feed and the recommendations so the
            # numbers always agree with what is shown.
            scored_candidates = []
            for product in products:
                if self.active_tasks.get(task_id, False):
                    score, reasoning = self._score_product(product, intent)
                    scored_candidates.append((score, product, reasoning))
            scored_candidates.sort(key=lambda x: x[0], reverse=True)
            TOP_RESULTS = 3
            final_products = [row[1] for row in scored_candidates[:TOP_RESULTS]]

            # Send products as they're found (bounded to the top 3)
            for product in final_products:
                if self.active_tasks.get(task_id, False):
                    await self._send_event(event_callback, ProductFoundEvent(
                        task_id=task_id,
                        product=product
                    ).model_dump())

            # Compare and rank products (already ranked above — no re-scoring)
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.COMPARING,
                message="Comparing products..."
            ).model_dump())

            recommendations = []
            for score, product, reasoning in scored_candidates[:TOP_RESULTS]:
                recommendations.append(Recommendation(
                    product=product,
                    score=score,
                    reasoning=reasoning,
                    matches_budget=product.price and product.price <= (intent.get('max_budget') or float('inf')),
                    matches_requirements=len(reasoning) > 0
                ))

            recommendations.sort(key=lambda x: x.score, reverse=True)
            top_recommendations = recommendations[:TOP_RESULTS]

            # Store per-task state so follow-up actions (select/compare/cross-sell/upsell) can run
            self.task_data[task_id] = {
                "query": request.query,
                "intent": intent,
                "products": products,
                "recommendations": top_recommendations,
                "selected_index": None,
            }
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.RECOMMENDING,
                message="Preparing final recommendations..."
            ).model_dump())
            
            await self._send_event(event_callback, FinalResultEvent(
                task_id=task_id,
                recommendations=top_recommendations,
                total_products_analyzed=len(products)
            ).model_dump())
            
            self.active_tasks[task_id] = False
            self._add_audit_log(task_id, "task_complete", "start_commerce_agent", "completed",
                              f"Task completed{' (partial after timeout)' if timed_out else ''}. Found {len(products)} products, recommended {len(top_recommendations)}")
            
            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.COMPLETED,
                message=(
                    "Search completed (partial result)".format()
                    if timed_out
                    else "Search completed successfully"
                )
            ).model_dump())
            
            return task_id
            
        except asyncio.CancelledError:
            # The background task was cancelled (STOP pressed). Clean up and mark inactive.
            self.active_tasks[task_id] = False
            self._add_audit_log(task_id, "task_cancelled", "start_commerce_agent", "cancelled",
                                "Background task cancelled by user")
            raise
        except Exception as e:
            self.active_tasks[task_id] = False
            self._add_audit_log(task_id, "task_error", "start_commerce_agent", "error", f"Error: {str(e)}")
            
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"Agent error: {str(e)}",
                error_type=type(e).__name__
            ).model_dump())
            
            logger.error(f"Commerce agent error: {e}", exc_info=True)
            raise
        finally:
            # Always release browser resources held by this task, whether it succeeded,
            # errored, timed out, or was cancelled via STOP.
            await self._cleanup_browser_sessions(task_id)
    
    async def cancel_task(self, task_id: str, event_callback: Optional[Callable] = None):
        """Cancel a running commerce agent task.

        Sets the cancellation flag (stops the browser-use should_stop callback), cancels the
        tracked background asyncio.Task (so the live browser run is torn down), cleans up any
        browser session, and sends a final cancelled event to Flutter.
        """
        if task_id not in self.active_tasks:
            if task_id:
                self._add_audit_log(task_id, "task_cancel_missing", "cancel_task", "not_found",
                                    "No active task found for cancellation")
            return False

        self.active_tasks[task_id] = False
        self._add_audit_log(task_id, "task_cancel", "cancel_task", "cancelled", "Task cancelled by user")

        # Hard-cancel the running background task (browser-use agent.run()).
        bg = self.background_tasks.get(task_id)
        if bg is not None and not bg.done():
            bg.cancel()

        # Clean up browser resources, then drop the background-task handle.
        await self._cleanup_browser_sessions(task_id)
        self.background_tasks.pop(task_id, None)

        await self._send_event(event_callback, CancelledEvent(
            task_id=task_id,
            message="Agent stopped by user"
        ).model_dump())

        return True

    async def _cleanup_browser_sessions(self, task_id: str) -> None:
        """Close all browser sessions registered for a task."""
        sessions = self.browser_sessions.pop(task_id, [])
        for session in sessions:
            await self.close_browser_session(session)

    async def close_browser_session(self, session: Optional[object]) -> None:
        if session is None:
            return

        try:
            await session.close()
        except Exception:
            try:
                session.close()
            except Exception:
                logger.warning("Browser session cleanup failed silently")

    # ------------------------------------------------------------------
    # Follow-up / growth actions (compare, cross-sell, upsell, confirm)
    # ------------------------------------------------------------------

    def _is_safe_message(self, message: str, task_id: str = None) -> bool:
        """Reject streaming messages that expose chain-of-thought or private details."""
        if not message:
            return False
        msg = message.lower()
        blocked = [
            "think", "thought", "reasoning step", "action_items", "memory",
            "selector", "xpath", "backend_node", "index=", "evaluate_previous_goal",
        ]
        if any(b in msg for b in blocked):
            return False
        return True

    def _get_task_product(self, task_id: str, index: int) -> Optional[ProductInfo]:
        """Resolve a product from the task's stored recommendations by 0-based index."""
        if task_id not in self.task_data:
            return None
        recs = self.task_data[task_id].get("recommendations", [])
        if 0 <= index < len(recs):
            return recs[index].product
        # fall back to all products
        products = self.task_data[task_id].get("products", [])
        if 0 <= index < len(products):
            return products[index]
        return None

    async def select_product(self, task_id: str, index: int, event_callback: Optional[Callable] = None) -> bool:
        """User selects a recommended product. Requests explicit confirmation before any bounded action."""
        product = self._get_task_product(task_id, index)
        if product is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"Product index {index} not found. Choose 1-{len(self.task_data.get(task_id, {}).get('recommendations', []))}.",
                error_type="NotFound"
            ).model_dump())
            return False

        if task_id in self.task_data:
            self.task_data[task_id]["selected_index"] = index

        self._add_audit_log(task_id, "product_selected", "select_product", "selected",
                            f"User selected: {product.name}", {"price": product.price, "url": product.source_url})

        # Explicit confirmation gate (spec: never auto-pay / never change amount without confirmation).
        # Only "open product page on the source site" is offered as the bounded action here.
        await self._send_event(event_callback, ConfirmationRequiredEvent(
            task_id=task_id,
            product=product,
            action_description=f"Open {product.name} on the source website so you can review it before deciding.",
        ).model_dump())
        return True

    async def confirm_selection(self, task_id: str, event_callback: Optional[Callable] = None) -> bool:
        """Explicit user confirmation after a selection. Performs the bounded, non-payment action."""
        if task_id not in self.task_data or self.task_data[task_id].get("selected_index") is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="No product selected to confirm. Select a product first.",
                error_type="NotFound"
            ).model_dump())
            return False

        index = self.task_data[task_id]["selected_index"]
        product = self._get_task_product(task_id, index)
        if product is None:
            return False

        self._add_audit_log(task_id, "selection_confirmed", "confirm_selection", "confirmed",
                            f"User confirmed: {product.name}", {"url": product.source_url})

        # Bounded, controlled action: open the verified source product page (no payment).
        source_url = product.source_url if product.source_url and product.source_url != "browser_search" else None

        await self._send_event(event_callback, SelectionConfirmedEvent(
            task_id=task_id,
            product=product,
            note=(f"Opening the source site for {product.name}." +
                  (" Opening is handled externally in the browser." if source_url else
                   " The source URL could not be captured; the product was found via a live browser search.")),
        ).model_dump())

        if source_url:
            await self._send_event(event_callback, BrowserActionEvent(
                task_id=task_id,
                action="open_source",
                message=f"Opening the verified product page for {product.name}...",
                url=source_url,
            ).model_dump())
        return True

    async def compare_products(self, task_id: str, indexes: List[int], event_callback: Optional[Callable] = None) -> bool:
        """Compare 2+ real products from the task against each other using extracted fields only."""
        products = [self._get_task_product(task_id, i) for i in indexes]
        products = [p for p in products if p is not None]

        if len(products) < 2:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="Compare needs at least 2 valid products.",
                error_type="NotFound"
            ).model_dump())
            return False

        self._add_audit_log(task_id, "compare", "compare_products", "completed",
                            f"Comparing {len(products)} products")

        # Build attribute-wise comparison lines from real extracted data only.
        all_attrs = {
            "Price": [f"₹{p.price}" if p.price else "Not available" for p in products],
            "Rating": [p.rating or "Not available" for p in products],
            "Availability": [p.availability or "Not available" for p in products],
            "Source": [self._domain(p.source_url) for p in products],
        }

        # Features as lines (name + feature list per product)
        comparison_lines = [
            ProductComparisonLine(attribute="Product", values=[p.name for p in products]),
        ]
        for attr, values in all_attrs.items():
            comparison_lines.append(ProductComparisonLine(attribute=attr, values=values))

        # Verdict based purely on extracted, comparable data.
        verdict = self._build_verdict(products)

        await self._send_event(event_callback, ComparisonEvent(
            task_id=task_id,
            compared_products=products,
            comparison_lines=comparison_lines,
            verdict=verdict,
        ).model_dump())
        return True

    def _domain(self, url: str) -> str:
        if not url or url == "browser_search":
            return "Live browser search"
        try:
            from urllib.parse import urlparse
            return urlparse(url).netloc or url
        except Exception:
            return url

    def _build_verdict(self, products: List[ProductInfo]) -> str:
        """Bare-bones verdict using only available extracted data."""
        lines = []
        for p in products:
            parts = [p.name]
            if p.price:
                parts.append(f"priced at ₹{p.price}")
            else:
                parts.append("price not captured")
            if p.rating:
                parts.append(f"rated {p.rating}")
            if p.availability:
                parts.append(p.availability.lower())
            lines.append(" • ".join(parts))
        return "Comparison based on live extracted data:\n" + "\n".join(lines)

    async def _run_targeted_task(self, task_id: str, prompt: str,
                                 event_callback: Optional[Callable] = None) -> List[ProductInfo]:
        """Run a secondary browser-use agent task (for cross-sell / upsell) and extract live products."""
        if not BROWSER_USE_AVAILABLE or not self.llm:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="browser-use or LLM not available for this action.",
                error_type="ConfigurationError"
            ).model_dump())
            return []

        async def should_stop_callback() -> bool:
            return not self.active_tasks.get(task_id, False)

        # Buffer the agent's per-step memory strings. Like the main run, these
        # reliably carry the product names + prices even when extracted_content()
        # is noisy or the run is cut short.
        collected_text: list[str] = []

        async def step_callback(state_summary, agent_output, step_number):
            if not self.active_tasks.get(task_id, False):
                return
            try:
                memory = getattr(agent_output, 'memory', None)
                if memory:
                    collected_text.append(str(memory))
                next_goal = getattr(agent_output, 'next_goal', None) or ''
                if next_goal and self._is_safe_message(next_goal, task_id):
                    await self._send_event(event_callback, BrowserActionEvent(
                        task_id=task_id,
                        action="agent_step",
                        message=next_goal,
                        url=getattr(state_summary, 'url', None) or None,
                    ).model_dump())
            except Exception as e:
                logger.warning(f"step callback error: {e}")

        browser_session = self._create_browser_session(task_id)
        agent = Agent(
            task=prompt,
            llm=self.llm,
            browser_session=browser_session,
            max_actions_per_step=5,
            max_failures=3,
            task_id=task_id,
            register_should_stop_callback=should_stop_callback,
            register_new_step_callback=step_callback,
        )

        timed_out = False
        try:
            history = await asyncio.wait_for(agent.run(), timeout=300)
        except asyncio.TimeoutError:
            # Same salvage policy as the main agent: keep whatever was already
            # collected instead of discarding it. 120s was too short for the
            # current browser-use version, which is why these tasks returned 0.
            logger.warning(
                f"[growth] Secondary browser task timed out for task {task_id}; "
                "returning products collected so far (partial result)."
            )
            history = agent.history if hasattr(agent, "history") else None
            timed_out = True
        finally:
            await self.close_browser_session(browser_session)

        # Merge every capture source and use the SAME hardened parser as the main
        # flow. The legacy _extract_products_from_history can't parse the agent's
        # markdown (name on one line, "Price:" on the next) so it returned zero
        # products even when the agent had found them.
        history_parts: list[str] = []
        if history:
            if hasattr(history, 'extracted_content'):
                history_parts.extend(history.extracted_content() or [])
            if hasattr(history, 'final_result'):
                try:
                    fr = history.final_result() or ""
                    if fr:
                        history_parts.append(fr)
                except Exception:
                    pass
        all_content = "\n".join(part for part in (("\n".join(collected_text)), "\n".join(history_parts)) if part)
        products = self._extract_structured_products(all_content)
        # Bounded: late secondary runs return at most 2-3 options, never a long list.
        products = products[:3]
        if not products:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="No products were found on the pages this time. Please click the button again to retry."
                + (" (the browser task timed out)" if timed_out else ""),
                error_type="EmptyResult"
            ).model_dump())
        return products

    async def cross_sell(self, task_id: str, index: int, event_callback: Optional[Callable] = None) -> bool:
        """After a selection, search live for relevant complementary (accessory) products."""
        base = self._get_task_product(task_id, index)
        if base is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="Cannot cross-sell: product not found.",
                error_type="NotFound"
            ).model_dump())
            return False

        # The main search task set active_tasks to False when it completed, so the
        # growth agent's should_stop_callback would stop it instantly at step 0
        # (log: "External callback requested stop"). Re-mark the task active for
        # the whole cross-sell run so the agent actually browses, product events
        # flow, and STOP/cancel keeps working — then restore it afterwards.
        self.active_tasks[task_id] = True
        try:
            self._add_audit_log(task_id, "cross_sell", "cross_sell", "started",
                                f"Cross-selling around: {base.name}")

            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.BROWSING,
                message=f"Searching live for compatible accessories for {base.name}..."
            ).model_dump())

            prompt = f"""
You are a shopping assistant looking for COMPLEMENTARY ACCESSORIES for the selected product: "{base.name}".

Do NOT re-find the same product type. Instead find compatible accessories/add-ons a buyer of this item would want.

Steps:
1. Search Google (google.com) for accessories compatible with "{base.name}".
2. Visit only 2-3 shopping websites from results (max 3). Do not keep opening new platforms.
3. Open each accessory's individual product page to confirm the details there.
4. For each accessory found, extract: exact name, live price (₹), key features, rating (if shown), availability, source URL.
5. Return 2-3 relevant accessories.

Only report products actually found on the pages. If price is missing write 'Not available'.
"""
            accessories = await self._run_targeted_task(task_id, prompt, event_callback)

            for acc in accessories:
                if self.active_tasks.get(task_id, False):
                    await self._send_event(event_callback, ProductFoundEvent(
                        task_id=task_id,
                        product=acc,
                    ).model_dump())

            await self._send_event(event_callback, GrowthResultEvent(
                task_id=task_id,
                growth_type="cross_sell",
                triggered_by=base,
                products=accessories,
                message=f"Found {len(accessories)} compatible accessories for {base.name}.",
            ).model_dump())

            self._add_audit_log(task_id, "cross_sell", "cross_sell", "completed",
                                f"Cross-sell returned {len(accessories)} accessories")
            return True
        finally:
            self.active_tasks[task_id] = False

    async def upsell(self, task_id: str, index: int, event_callback: Optional[Callable] = None) -> bool:
        """If a selected/low-scoring product closely misses requirements, search live for a better (typically higher-end) alternative."""
        base = self._get_task_product(task_id, index)
        if base is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="Cannot upsell: product not found.",
                error_type="NotFound"
            ).model_dump())
            return False

        state = self.task_data.get(task_id, {})
        intent = state.get("intent", {})

        # Same active-flag fix as cross_sell: the main search already completed and
        # set active_tasks to False, which would make should_stop_callback stop the
        # growth agent at its first step. Re-activate for this whole run.
        self.active_tasks[task_id] = True
        try:
            self._add_audit_log(task_id, "upsell", "upsell", "started",
                                f"Upsell based on: {base.name}")

            await self._send_event(event_callback, AgentStatusEvent(
                task_id=task_id,
                status=AgentStatus.RECOMMENDING,
                message=f"Searching for a better alternative to {base.name} (closes your requirements more closely)..."
            ).model_dump())

            requirements = intent.get('requirements') or []
            use_case = intent.get('use_case')
            max_budget = intent.get('max_budget')
            req_text = ", ".join(requirements) if requirements else "the originally requested features"
            budget_text = f"under ₹{max_budget}" if max_budget else "within a reasonable budget"

            prompt = f"""
You are a shopping assistant recommending a BETTER UPGRADE to a product that missed the user's requirements.

Original request: "{state.get('query', '')}"
Selected/considered product: "{base.name}" at {'₹' + str(base.price) if base.price else 'unknown price'}.

The goal: find ONE clearly better alternative (better features, better value, or a mild step-up) {budget_text}
that satisfies: {req_text} and use case: {use_case or 'general'}.

Steps:
1. Search Google (google.com) for a better alternative to "{base.name}" {budget_text}.
2. Visit only 2-3 shopping websites from results (max 3). Do not keep opening new platforms.
3. Open the alternative's individual product page to confirm the details there.
4. Extract for the best alternative: exact name, live price (₹), key features, rating, availability, source URL.
5. In your final summary, explain HOW/WHY this alternative improves on "{base.name}" and whether it is above the original budget.

Only report products actually found on live pages. Never invent prices.
"""
            alts = await self._run_targeted_task(task_id, prompt, event_callback)

            for alt in alts:
                if self.active_tasks.get(task_id, False):
                    await self._send_event(event_callback, ProductFoundEvent(
                        task_id=task_id,
                        product=alt,
                    ).model_dump())

            await self._send_event(event_callback, GrowthResultEvent(
                task_id=task_id,
                growth_type="upsell",
                triggered_by=base,
                products=alts,
                message=f"Found {len(alts)} better alternative(s) to {base.name}.",
            ).model_dump())

            self._add_audit_log(task_id, "upsell", "upsell", "completed",
                                f"Upsell returned {len(alts)} alternative(s)")
            return True
        finally:
            self.active_tasks[task_id] = False

    # ------------------------------------------------------------------
    # Phase 4 — Merchant checkout with Razorpay test payment
    #
    # Money actions are BOUNDED and GATED:
    #   checkout()            -> build order, request explicit approval (no money moved)
    #   approve_payment()     -> user approved -> create Razorpay order (still no charge)
    #   confirm_payment()     -> client reports the completed payment -> verify -> resolve
    #
    # The agent NEVER pays or charges autonomously; approval is always required.
    # ------------------------------------------------------------------

    def _get_order(self, task_id: str) -> Optional[Order]:
        state = self.task_data.get(task_id, {})
        return state.get("pending_order")

    def _store_order(self, task_id: str, order: Order) -> None:
        state = self.task_data.setdefault(task_id, {})
        state["pending_order"] = order

    def _resolve_catalog_product(self, product: ProductInfo) -> Optional[MerchantProduct]:
        """Map a ProductInfo back to a merchant catalog product (if possible).

        Falls back to matching by catalogue id if source_url is 'waflo-merchant:<id>',
        otherwise by a fuzzy name match so demo stays deterministic.
        """
        src = product.source_url or ""
        if src.startswith("waflo-merchant:"):
            pid = src.split(":", 1)[1]
            catalog = self.merchant_catalog.get_product(pid)
            if catalog:
                return catalog
        base = product.name.lower().strip()
        for p in self.merchant_catalog.list_products():
            if base == p.name.lower() or base in p.name.lower() or p.name.lower() in base:
                return p
        return None

    async def checkout(
        self,
        task_id: str,
        index: int,
        quantity: int = 1,
        event_callback: Optional[Callable] = None,
    ) -> bool:
        """Start the bounded checkout for a recommended product.

        Does NOT create any charge. Sends a CheckoutReadyEvent that requires the
        user to explicitly approve before an order / payment is created.
        """
        product = self._get_task_product(task_id, index)
        if product is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"Product index {index} not found. Choose 1-{len(self.task_data.get(task_id, {}).get('recommendations', []))}.",
                error_type="NotFound",
            ).model_dump())
            return False

        if product.price is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"'{product.name}' has no captured price, so it cannot be checked out.",
                error_type="PricingUnavailable",
            ).model_dump())
            return False

        qty = max(1, int(quantity or 1))
        amount = round(product.price * qty, 2)

        # ---- Phase 6: Budget / policy guard ----
        # Enforce user-defined constraints BEFORE any order or payment exists.
        # The agent must never create a bounded action that violates policy.
        state = self.task_data.setdefault(task_id, {})
        intent = state.get("intent", {}) or {}
        max_budget = intent.get("max_budget")
        if max_budget is not None and amount > max_budget:
            self._add_audit_log(
                task_id, "checkout_blocked", "policy_guard", "blocked",
                f"Purchase of '{product.name}' for ₹{amount} exceeds budget cap ₹{max_budget}. No order/payment created.",
                {"price": product.price, "qty": qty, "amount": amount,
                 "max_budget": max_budget, "product": product.name},
            )
            await self._send_event(event_callback, CheckoutBlockedEvent(
                task_id=task_id,
                product=product,
                amount=amount,
                max_budget=max_budget,
                reason=(
                    f"This product costs ₹{amount}, which exceeds your ₹{max_budget} "
                    "budget. I won't create a payment order. Try a cheaper option or "
                    "increase your budget range."
                ),
            ).model_dump())
            return False

        order = Order(
            order_id=f"WF-{uuid4().hex[:8].upper()}",
            task_id=task_id,
            items=[
                OrderItem(
                    product_id="catalog" if self._resolve_catalog_product(product) else "live",
                    name=product.name,
                    quantity=qty,
                    unit_price=product.price,
                )
            ],
            amount=amount,
            status=OrderStatus.PENDING,
            approval_required=True,
            reason=f"Checkout of '{product.name}' (qty {qty}) at ₹{amount}",
        )
        self._store_order(task_id, order)

        self._add_audit_log(
            task_id, "checkout_initiated", "checkout", "pending",
            f"Checkout requested for: {product.name} | amount ₹{amount}",
            {"price": product.price, "qty": qty, "amount": amount,
             "url": product.source_url, "order_id": order.order_id},
        )

        await self._send_event(event_callback, CheckoutReadyEvent(
            task_id=task_id,
            product=product,
            amount=amount,
            action_description=(
                f"Create an order for {qty} x {product.name} for ₹{amount}. "
                "You must approve before any payment is created. No money is charged at this step."
            ),
        ).model_dump())

        # Remember the selected product so approve/confirm can reference it.
        state = self.task_data.setdefault(task_id, {})
        state["selected_index"] = index
        state["checkout"] = {
            "product": product.model_dump(),
            "order_id": order.order_id,
            "amount": amount,
            "approval_granted": False,
        }
        return True

    async def approve_payment(
        self,
        task_id: str,
        event_callback: Optional[Callable] = None,
    ) -> bool:
        """The user has explicitly approved the pending checkout.

        Creates the Razorpay order (in test mode / demo mode). Still does NOT
        charge the user — it only prepares a payment that the client then runs.
        """
        order = self._get_order(task_id)
        if order is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="No pending checkout to approve. Call checkout() first.",
                error_type="NotFound",
            ).model_dump())
            return False

        if order.status != OrderStatus.PENDING:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"Checkout already {order.status.value}; cannot re-approve.",
                error_type="StateError",
            ).model_dump())
            return False

        state = self.task_data.get(task_id, {})
        checkout = state.get("checkout", {})
        checkout["approval_granted"] = True
        state["checkout"] = checkout

        order.status = OrderStatus.APPROVED
        order.approval_granted = True
        order.receipt = f"waflo_{task_id[-8:]}"
        order.updated_at = datetime.utcnow()

        # Create the Razorpay order (bounded: creates a payment, charges nothing).
        try:
            order = self.razorpay.create_order(order)
        except RazorpayServiceError as e:
            order.status = OrderStatus.FAILED
            self._store_order(task_id, order)
            self._add_audit_log(task_id, "razorpay_order_failed", "approve_payment", "error",
                                f"Razorpay order creation failed: {e}")
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message=f"Could not create the payment order: {e}",
                error_type="RazorpayError",
            ).model_dump())
            return False

        self._store_order(task_id, order)
        self._add_audit_log(task_id, "order_created", "approve_payment", "approved",
                            f"Order {order.order_id} approved; Razorpay order {order.razorpay_order_id}",
                            {"order_id": order.order_id,
                             "razorpay_order_id": order.razorpay_order_id,
                             "amount": order.amount})

        await self._send_event(event_callback, OrderCreatedEvent(
            task_id=task_id,
            order=order,
        ).model_dump())

        await self._send_event(event_callback, PaymentInitiatedEvent(
            task_id=task_id,
            order_id=order.order_id,
            razorpay_order_id=order.razorpay_order_id,
            amount=order.amount,
            key_id=self.razorpay.key_id if self.razorpay.configured else None,
            test_mode=self.razorpay.test_mode,
        ).model_dump())
        return True

    async def confirm_payment(
        self,
        task_id: str,
        payment_id: str,
        signature: Optional[str] = None,
        event_callback: Optional[Callable] = None,
    ) -> bool:
        """Resolve a completed payment reported back from the client/webhook.

        This is where the actual success/failure is determined and recorded.
        """
        order = self._get_order(task_id)
        if order is None:
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="No order found to confirm payment for.",
                error_type="NotFound",
            ).model_dump())
            return False

        if order.status == OrderStatus.PAID:
            await self._send_event(event_callback, PaymentSuccessEvent(
                task_id=task_id,
                order_id=order.order_id,
                razorpay_payment_id=order.razorpay_payment_id,
                amount=order.amount,
                message="Payment was already confirmed for this order.",
            ).model_dump())
            return True

        payment_id = payment_id or ""
        try:
            status = self.razorpay.resolve_payment_status(order, payment_id, signature)
        except RazorpayServiceError as e:
            order.status = OrderStatus.FAILED
            self._store_order(task_id, order)
            self._add_audit_log(task_id, "payment_verify_error", "confirm_payment", "error",
                                f"Payment verification failed: {e}")
            await self._send_event(event_callback, PaymentFailedEvent(
                task_id=task_id,
                order_id=order.order_id,
                amount=order.amount,
                reason=str(e),
                recovered=False,
            ).model_dump())
            return False

        order.status = status
        order.updated_at = datetime.utcnow()

        if status == OrderStatus.PAID:
            order.razorpay_payment_id = payment_id
            self._store_order(task_id, order)
            self._add_audit_log(task_id, "payment_success", "confirm_payment", "completed",
                                f"Payment succeeded for order {order.order_id}",
                                {"order_id": order.order_id, "payment_id": payment_id,
                                 "amount": order.amount})
            await self._send_event(event_callback, PaymentSuccessEvent(
                task_id=task_id,
                order_id=order.order_id,
                razorpay_payment_id=payment_id,
                amount=order.amount,
                message=f"Purchase successful. Order {order.order_id} paid ₹{order.amount}.",
            ).model_dump())
            return True

        order.status = OrderStatus.FAILED
        self._store_order(task_id, order)
        self._add_audit_log(task_id, "payment_failed", "confirm_payment", "error",
                            f"Payment failed for order {order.order_id}",
                            {"order_id": order.order_id, "payment_id": payment_id or "unknown",
                             "amount": order.amount})

        # Recovery: allow the user to retry by resetting to PENDING (still gated).
        # We surface a PaymentFailedEvent and let the client call approve again.
        order.status = OrderStatus.PENDING
        order.approval_granted = False
        order.razorpay_order_id = None
        self._store_order(task_id, order)

        await self._send_event(event_callback, PaymentFailedEvent(
            task_id=task_id,
            order_id=order.order_id,
            amount=order.amount,
            reason="Payment did not complete. You can retry after re-approving.",
            recovered=True,
        ).model_dump())
        return False

    async def cancel_checkout(
        self,
        task_id: str,
        event_callback: Optional[Callable] = None,
    ) -> bool:
        """Cancel a pending checkout before any payment is made."""
        order = self._get_order(task_id)
        if order is None or order.status not in (OrderStatus.PENDING, OrderStatus.APPROVED):
            await self._send_event(event_callback, ErrorEvent(
                task_id=task_id,
                message="No cancellable checkout found.",
                error_type="NotFound",
            ).model_dump())
            return False

        order.status = OrderStatus.CANCELLED
        self._store_order(task_id, order)
        self._add_audit_log(task_id, "checkout_cancelled", "cancel_checkout", "cancelled",
                            f"Checkout for order {order.order_id} cancelled by user")
        return True

    def get_order(self, task_id: str) -> Optional[Order]:
        """Return the stored order for a task (used by HTTP endpoints)."""
        return self._get_order(task_id)

    def get_audit_logs(self, task_id: Optional[str] = None) -> List[AuditLogEntry]:
        """Get audit logs, optionally filtered by task_id"""
        if task_id:
            persistent_logs = self.audit_service.get_audit_logs(task_id)
            if persistent_logs:
                return persistent_logs
            return [log for log in self.audit_logs if log.task_id == task_id]
        return self.audit_logs