import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Raised when the Razorpay checkout cannot be loaded or invoked.
class RazorpayCheckoutException implements Exception {
  final String message;
  RazorpayCheckoutException(this.message);
  @override
  String toString() => message;
}

/// Result of a completed Razorpay checkout payment.
class RazorpayPaymentResult {
  final String paymentId;
  final String orderId;
  final String signature;
  RazorpayPaymentResult(this.paymentId, this.orderId, this.signature);
}

/// Thin client for Razorpay's hosted Checkout modal (Flutter Web).
///
/// Loads Razorpay's checkout.js at runtime, then opens Razorpay's hosted
/// checkout with the order the backend already created (Razorpay test mode).
/// On success it returns the `payment_id` + `signature` that should be
/// forwarded to the backend `/confirm_payment` endpoint for server-side
/// verification (kept secret-free on the client).
class RazorpayCheckout {
  static Completer<void>? _scriptCompleter;

  /// Ensure Razorpay's checkout.js is present on the page (idempotent).
  static Future<void> ensureScriptLoaded() async {
    if (_scriptCompleter != null) return _scriptCompleter!.future;
    if (globalContext.has('Razorpay')) return;

    final completer = Completer<void>();
    _scriptCompleter = completer;

    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    script.addEventListener('load', ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS);
    script.addEventListener('error', ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          RazorpayCheckoutException('Could not load Razorpay Checkout SDK'),
        );
      }
    }).toJS);
    web.document.head?.appendChild(script);

    return completer.future;
  }

  /// Open Razorpay's hosted Checkout modal.
  ///
  /// [keyId]   — the Razorpay key id (provided by the backend).
  /// [orderId] — the Razorpay order id created via the backend.
  /// [amountPaise] — the amount to charge, in paise.
  static Future<void> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String currency,
    required String name,
    required String description,
    required void Function(RazorpayPaymentResult result) onSuccess,
    required void Function(String message) onFailure,
  }) async {
    await ensureScriptLoaded();

    if (!globalContext.has('Razorpay')) {
      throw RazorpayCheckoutException('Razorpay Checkout SDK is not available');
    }

    final theme = JSObject();
    theme.setProperty('color'.toJS, '#00897b'.toJS);

    final modal = JSObject();
    modal.setProperty('ondismiss'.toJS, (() {
      onFailure('Payment cancelled by user');
    }).toJS);

    final opts = JSObject();
    opts.setProperty('key'.toJS, keyId.toJS);
    opts.setProperty('order_id'.toJS, orderId.toJS);
    opts.setProperty('amount'.toJS, amountPaise.toJS);
    opts.setProperty('currency'.toJS, currency.toJS);
    opts.setProperty('name'.toJS, name.toJS);
    opts.setProperty('description'.toJS, description.toJS);
    opts.setProperty('theme'.toJS, theme);
    opts.setProperty('modal'.toJS, modal);
    opts.setProperty(
      'handler'.toJS,
      ((JSObject response) {
        final result = RazorpayPaymentResult(
          (response['razorpay_payment_id'] as JSString?)?.toDart ?? '',
          (response['razorpay_order_id'] as JSString?)?.toDart ?? '',
          (response['razorpay_signature'] as JSString?)?.toDart ?? '',
        );
        onSuccess(result);
      }).toJS,
    );

    // `new Razorpay(opts)` then call `.open()`.
    final ctor = globalContext.getProperty<JSFunction>('Razorpay'.toJS);
    final checkout = ctor.callAsConstructor<JSObject>(opts);
    checkout.callMethod<JSAny?>('open'.toJS);
  }
}
