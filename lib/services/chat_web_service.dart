import 'dart:async';
import 'dart:convert';
import 'package:web_socket_client/web_socket_client.dart';

class ChatWebService {
  static final _instance = ChatWebService._internal();
  WebSocket? _socket;

  factory ChatWebService() => _instance;

  ChatWebService._internal();

  /// Every incoming WebSocket message, re-broadcast. Used by the Agent Hub
  /// executors so they can observe the live chat/search backend flow.
  final _realtimeController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get realtimeStream => _realtimeController.stream;

  final _searchResultController = StreamController<Map<String, dynamic>>.broadcast();
  final _contentController = StreamController<Map<String, dynamic>>.broadcast();
  final _imagesController = StreamController<List<String>>.broadcast();
  final _generatedImageController = StreamController<String>.broadcast();
  
  // Commerce agent streams
  final _agentStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _browserActionController = StreamController<Map<String, dynamic>>.broadcast();
  final _productFoundController = StreamController<Map<String, dynamic>>.broadcast();
  final _finalResultController = StreamController<Map<String, dynamic>>.broadcast();
  final _commerceErrorController = StreamController<Map<String, dynamic>>.broadcast();
  final _commerceCancelledController = StreamController<Map<String, dynamic>>.broadcast();
  final _commerceStartedController = StreamController<Map<String, dynamic>>.broadcast();
  // Agent Hub browse (Strobi / browser-use) stream
  final _browseStartedController = StreamController<Map<String, dynamic>>.broadcast();
  // Growth action streams
  final _confirmationRequiredController = StreamController<Map<String, dynamic>>.broadcast();
  final _selectionConfirmedController = StreamController<Map<String, dynamic>>.broadcast();
  final _comparisonController = StreamController<Map<String, dynamic>>.broadcast();
  final _growthResultController = StreamController<Map<String, dynamic>>.broadcast();
  // Checkout / payment streams (Phase 4 Razorpay)
  final _checkoutReadyController = StreamController<Map<String, dynamic>>.broadcast();
  final _checkoutBlockedController = StreamController<Map<String, dynamic>>.broadcast();
  final _orderCreatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _paymentInitiatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _paymentSuccessController = StreamController<Map<String, dynamic>>.broadcast();
  final _paymentFailedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get searchResultStream =>
      _searchResultController.stream;
  Stream<Map<String, dynamic>> get contentStream => _contentController.stream;
  Stream<List<String>> get imagesStream => _imagesController.stream;
  Stream<String> get generatedImageStream => _generatedImageController.stream;
  
  // Commerce streams
  Stream<Map<String, dynamic>> get agentStatusStream => _agentStatusController.stream;
  Stream<Map<String, dynamic>> get browserActionStream => _browserActionController.stream;
  Stream<Map<String, dynamic>> get productFoundStream => _productFoundController.stream;
  Stream<Map<String, dynamic>> get finalResultStream => _finalResultController.stream;
  Stream<Map<String, dynamic>> get commerceErrorStream => _commerceErrorController.stream;
  Stream<Map<String, dynamic>> get commerceCancelledStream => _commerceCancelledController.stream;
  Stream<Map<String, dynamic>> get commerceStartedStream => _commerceStartedController.stream;
  Stream<Map<String, dynamic>> get browseStartedStream => _browseStartedController.stream;
  // Growth action streams
  Stream<Map<String, dynamic>> get confirmationRequiredStream => _confirmationRequiredController.stream;
  Stream<Map<String, dynamic>> get selectionConfirmedStream => _selectionConfirmedController.stream;
  Stream<Map<String, dynamic>> get comparisonStream => _comparisonController.stream;
  Stream<Map<String, dynamic>> get growthResultStream => _growthResultController.stream;
  // Checkout / payment streams
  Stream<Map<String, dynamic>> get checkoutReadyStream => _checkoutReadyController.stream;
  Stream<Map<String, dynamic>> get checkoutBlockedStream => _checkoutBlockedController.stream;
  Stream<Map<String, dynamic>> get orderCreatedStream => _orderCreatedController.stream;
  Stream<Map<String, dynamic>> get paymentInitiatedStream => _paymentInitiatedController.stream;
  Stream<Map<String, dynamic>> get paymentSuccessStream => _paymentSuccessController.stream;
  Stream<Map<String, dynamic>> get paymentFailedStream => _paymentFailedController.stream;

  void connect() {
    _socket = WebSocket(Uri.parse("ws://localhost:8000/ws/chat"));

    _socket!.messages.listen((message) {
      final data = json.decode(message);
      _realtimeController.add(data);
      print('Received message type: ${data['type']}');
      
      // Handle existing chat events
      if (data['type'] == 'search_result') {
        _searchResultController.add(data);
      } else if (data['type'] == 'content') {
        _contentController.add(data);
      } else if (data['type'] == 'web_images') {
        List<String> images = List<String>.from(data['data']);
        _imagesController.add(images);
      } else if (data['type'] == 'generated_image') {
        _generatedImageController.add(data['data']);
      }
      // Handle commerce events
      else if (data['type'] == 'agent_status') {
        _agentStatusController.add(data);
      } else if (data['type'] == 'browser_action') {
        _browserActionController.add(data);
      } else if (data['type'] == 'product_found') {
        _productFoundController.add(data);
      } else if (data['type'] == 'final_result') {
        _finalResultController.add(data);
      } else if (data['type'] == 'error' && data.containsKey('task_id')) {
        _commerceErrorController.add(data);
      } else if (data['type'] == 'cancelled') {
        _commerceCancelledController.add(data);
      } else if (data['type'] == 'commerce_started') {
        print('Commerce agent started: ${data['task_id']}');
        _commerceStartedController.add(data);
      } else if (data['type'] == 'browse_started') {
        print('Browse agent started: ${data['task_id']}');
        _browseStartedController.add(data);
      } else if (data['type'] == 'commerce_cancelled') {
        print('Commerce agent cancelled: ${data['task_id']}');
      } else if (data['type'] == 'confirmation_required') {
        _confirmationRequiredController.add(data);
      } else if (data['type'] == 'selection_confirmed') {
        _selectionConfirmedController.add(data);
      } else if (data['type'] == 'comparison') {
        _comparisonController.add(data);
      } else if (data['type'] == 'growth_result') {
        _growthResultController.add(data);
      }
      // Phase 4 checkout / payment events
      else if (data['type'] == 'checkout_ready') {
        print('Checkout ready: ${data['order_id'] ?? data['task_id']}');
        _checkoutReadyController.add(data);
      } else if (data['type'] == 'checkout_blocked') {
        _checkoutBlockedController.add(data);
      } else if (data['type'] == 'order_created') {
        _orderCreatedController.add(data);
      } else if (data['type'] == 'payment_initiated') {
        _paymentInitiatedController.add(data);
      } else if (data['type'] == 'payment_success') {
        _paymentSuccessController.add(data);
      } else if (data['type'] == 'payment_failed') {
        _paymentFailedController.add(data);
      }
    });
  }

  void chat(String query, {String? fileName, String? fileBase64}) {
    print(query);
    print(_socket);
    final payload = {'query': query};
    if (fileName != null && fileBase64 != null) {
      payload['file_name'] = fileName;
      payload['file_base64'] = fileBase64;
    }
    unawaited(_sendAgentPayload(payload, _agentSendFailedMessage));
  }

  /// Web-research (Cosmo) entry point — the standard `{"query": ...}` chat.
  /// Guarded exactly like the commerce sends so the agent never crashes the
  /// app on a dead socket; failures surface as typed `error` events on
  /// [realtimeStream], which ResearchExecutor renders.
  static const _agentSendFailedMessage =
      'Could not reach the Waflo backend right now. '
      'Make sure it is running, then try again.';

  void sendChatMessage(String query) {
    print('Research agent request: $query');
    unawaited(_sendAgentPayload({'query': query}, _agentSendFailedMessage));
  }

  /// Writing (Sunny) entry point — the backend's `writing` request type runs a
  /// pure LLM draft with no web search.
  void writeText(String query) {
    print('Writing agent request: $query');
    unawaited(_sendAgentPayload(
        {'type': 'writing', 'query': query}, _agentSendFailedMessage));
  }

  Future<void> _sendAgentPayload(
      Map<String, dynamic> payload, String failureMessage) async {
    final ok = await _ensureCanSend();
    if (!ok) {
      _realtimeController.add({'type': 'error', 'data': failureMessage});
      return;
    }
    try {
      _socket!.send(json.encode(payload));
    } catch (e) {
      _realtimeController.add({'type': 'error', 'data': 'Agent send failed: $e'});
    }
  }
  
  void startCommerceAgent(String query, {double? maxBudget, String? useCase, List<String>? requirements}) {
    print('Starting commerce agent: $query');
    final payload = {
      'type': 'commerce',
      'action': 'start',
      'query': query,
    };
    if (maxBudget != null) payload['max_budget'] = maxBudget.toString();
    if (useCase != null) payload['use_case'] = useCase;
    if (requirements != null) payload['requirements'] = requirements.join(',');

    unawaited(_sendCommerce(payload, _commerceSendFailedMessage));
  }

  void cancelCommerceAgent(String taskId) {
    print('Cancelling commerce agent: $taskId');
    unawaited(_sendCommerce(
      {'type': 'commerce', 'action': 'cancel', 'task_id': taskId},
      'Could not cancel the shopping agent (backend disconnected).',
    ));
  }

  /// Safety net for every commerce action. The WebSocket auto-reconnects, but
  /// `send()` on a dropped channel is a silent no-op, which left the commerce
  /// UI stuck on "Searching…" forever. Guard like the browse flow does: wait a
  /// bounded time for the connection, otherwise surface a typed error event
  /// the commerce page already renders.
  static const _commerceSendFailedMessage =
      'Could not reach the shopping backend right now. '
      'Make sure it is running, then try again.';

  Future<void> _sendCommerce(
      Map<String, dynamic> payload, String failureMessage) async {
    final ok = await _ensureCanSend();
    if (!ok) {
      _commerceErrorController.add(
        {'type': 'error', 'message': failureMessage},
      );
      return;
    }
    try {
      _socket!.send(json.encode(payload));
    } catch (e) {
      _commerceErrorController.add(
        {'type': 'error', 'message': 'Shopping agent send failed: $e'},
      );
    }
  }

  /// Start a web-research (Strobi) task that drives the vendored browser-use
  /// agent on the backend. Live steps arrive on [realtimeStream] as
  /// `agent_step` / `content` / `done` / `error` / `browse_cancelled`.
  ///
  /// The connection is verified before sending: if the WebSocket is dead or
  /// reconnecting (e.g. after a backend restart), we wait for the client to
  /// recover the connection and only then send. If the socket cannot be made
  /// ready within a bounded timeout, a local `error` event is emitted so the
  /// caller never waits forever on a message that vanished.
  void startBrowse(String query) {
    print('Starting browse agent: $query');
    unawaited(_sendBrowse(query));
  }

  static const _browseSendTimeout = Duration(seconds: 12);

  /// Returns true once the WebSocket is able to transmit.
  ///
  /// `web_socket_client` auto-reconnects with backoff, but its `send()` is a
  /// silent no-op while the channel is dropped (i.e. `Reconnecting`/dead), so
  /// we must explicitly wait for a live connection before sending.
  Future<bool> _ensureCanSend() async {
    var socket = _socket;
    if (socket == null) {
      connect();
      socket = _socket;
    }
    final ws = socket;
    if (ws == null) return false;
    final deadline = DateTime.now().add(_browseSendTimeout);
    while (true) {
      final state = ws.connection.state;
      if (state is Connected || state is Reconnected) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _sendBrowse(String query) async {
    final ok = await _ensureCanSend();
    if (!ok) {
      // Emit the failure locally over realtimeStream so the Strobi executor
      // terminates instead of hanging on "Strobi is on it…".
      _realtimeController.add({
        'type': 'error',
        'message': 'Could not reach the browser backend (the WebSocket is '
            'disconnected). Start the backend and try again.',
      });
      return;
    }
    try {
      _socket!.send(json.encode({
        'type': 'browse',
        'action': 'start',
        'query': query,
      }));
    } catch (e) {
      _realtimeController.add({'type': 'error', 'message': 'Browse send failed: $e'});
    }
  }

  void cancelBrowse(String taskId) {
    print('Cancelling browse agent: $taskId');
    unawaited(_sendAgentPayload(
      {'type': 'browse', 'action': 'cancel', 'task_id': taskId},
      'Could not cancel the browser agent (backend disconnected).',
    ));
  }

  void selectCommerceProduct(String taskId, int index) {
    unawaited(_sendCommerce(
      {'type': 'commerce', 'action': 'select', 'task_id': taskId, 'index': index},
      _commerceSendFailedMessage,
    ));
  }

  void confirmCommerceSelection(String taskId) {
    unawaited(_sendCommerce(
      {'type': 'commerce', 'action': 'confirm', 'task_id': taskId},
      _commerceSendFailedMessage,
    ));
  }

  void compareCommerceProducts(String taskId, List<int> indexes) {
    unawaited(_sendCommerce(
      {
        'type': 'commerce',
        'action': 'compare',
        'task_id': taskId,
        'indexes': indexes,
      },
      _commerceSendFailedMessage,
    ));
  }

  void crossSellCommerce(String taskId, int index) {
    unawaited(_sendCommerce(
      {
        'type': 'commerce',
        'action': 'cross_sell',
        'task_id': taskId,
        'index': index,
      },
      'Could not find accessories (backend disconnected).',
    ));
  }

  void upsellCommerce(String taskId, int index) {
    unawaited(_sendCommerce(
      {
        'type': 'commerce',
        'action': 'upsell',
        'task_id': taskId,
        'index': index,
      },
      'Could not find alternatives (backend disconnected).',
    ));
  }

  // ---- Phase 4: Merchant checkout with Razorpay test payment ----

  void checkoutCommerce(String taskId, int index, {int quantity = 1}) {
    unawaited(_sendCommerce(
      {
        'type': 'commerce',
        'action': 'checkout',
        'task_id': taskId,
        'index': index,
        'quantity': quantity,
      },
      _commerceSendFailedMessage,
    ));
  }

  void approveCommercePayment(String taskId) {
    unawaited(_sendCommerce(
      {'type': 'commerce', 'action': 'approve', 'task_id': taskId},
      _commerceSendFailedMessage,
    ));
  }

  void confirmCommercePayment(String taskId, String paymentId,
      {String? signature}) {
    unawaited(_sendCommerce(
      {
        'type': 'commerce',
        'action': 'confirm_payment',
        'task_id': taskId,
        'payment_id': paymentId,
        'signature': ?signature,
      },
      'Could not confirm the payment (backend disconnected).',
    ));
  }

  void cancelCommerceCheckout(String taskId) {
    unawaited(_sendCommerce(
      {'type': 'commerce', 'action': 'cancel_checkout', 'task_id': taskId},
      'Could not cancel the checkout (backend disconnected).',
    ));
  }
}