import 'dart:async';
import 'dart:convert';
import 'package:web_socket_client/web_socket_client.dart';

class ChatWebService {
  static final _instance = ChatWebService._internal();
  WebSocket? _socket;

  factory ChatWebService() => _instance;

  ChatWebService._internal();
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
    _socket!.send(json.encode(payload));
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
    
    _socket!.send(json.encode(payload));
  }
  
  void cancelCommerceAgent(String taskId) {
    print('Cancelling commerce agent: $taskId');
    final payload = {
      'type': 'commerce',
      'action': 'cancel',
      'task_id': taskId,
    };
    _socket!.send(json.encode(payload));
  }

  void selectCommerceProduct(String taskId, int index) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'select',
      'task_id': taskId,
      'index': index,
    }));
  }

  void confirmCommerceSelection(String taskId) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'confirm',
      'task_id': taskId,
    }));
  }

  void compareCommerceProducts(String taskId, List<int> indexes) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'compare',
      'task_id': taskId,
      'indexes': indexes,
    }));
  }

  void crossSellCommerce(String taskId, int index) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'cross_sell',
      'task_id': taskId,
      'index': index,
    }));
  }

  void upsellCommerce(String taskId, int index) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'upsell',
      'task_id': taskId,
      'index': index,
    }));
  }

  // ---- Phase 4: Merchant checkout with Razorpay test payment ----

  void checkoutCommerce(String taskId, int index, {int quantity = 1}) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'checkout',
      'task_id': taskId,
      'index': index,
      'quantity': quantity,
    }));
  }

  void approveCommercePayment(String taskId) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'approve',
      'task_id': taskId,
    }));
  }

  void confirmCommercePayment(String taskId, String paymentId, {String? signature}) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'confirm_payment',
      'task_id': taskId,
      'payment_id': paymentId,
      'signature': ?signature,
    }));
  }

  void cancelCommerceCheckout(String taskId) {
    _socket!.send(json.encode({
      'type': 'commerce',
      'action': 'cancel_checkout',
      'task_id': taskId,
    }));
  }
}