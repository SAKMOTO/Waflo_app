import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/services/razorpay_checkout.dart';
import 'package:waflo_app/widgets/commerce_agent_timeline.dart';
import 'package:waflo_app/widgets/commerce_product_card.dart';
import 'package:waflo_app/widgets/commerce_controls.dart';
import 'package:waflo_app/widgets/side_bar.dart';

class CommercePage extends StatefulWidget {
  final String? initialQuery;
  const CommercePage({super.key, this.initialQuery});

  @override
  State<CommercePage> createState() => _CommercePageState();
}

class _CommercePageState extends State<CommercePage> {
  final ChatWebService _chatService = ChatWebService();
  final TextEditingController _queryController = TextEditingController();
  
  List<Map<String, dynamic>> _agentActivities = [];
  List<Map<String, dynamic>> _foundProducts = [];
  List<Map<String, dynamic>> _recommendations = [];
  String? _currentTaskId;
  bool _isAgentRunning = false;
  String _agentStatus = '';
  int? _selectedIndex;
  Map<String, dynamic>? _pendingConfirmation;
  Map<String, dynamic>? _comparisonData;
  List<Map<String, dynamic>> _growthProducts = [];
  String _growthTitle = '';
  bool _isGrowthLoading = false;
  String? _growthError;

  // Phase 4 — checkout / payment state
  Map<String, dynamic>? _checkoutReady;      // approval gate payload
  Map<String, dynamic>? _checkoutBlocked;    // policy-guard rejection
  Map<String, dynamic>? _paymentInitiated;   // razorpay order created
  Map<String, dynamic>? _paymentResult;      // success or failure
  bool _isPaymentSuccess = false;
  String? _lastOrderId;

  @override
  void initState() {
    super.initState();
    _setupCommerceStreams();
    // Remove web-ui launcher and handle initial query
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _queryController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startAgent();
      });
    }
  }

  void _setupCommerceStreams() {
    // Listen to agent status updates
    _chatService.agentStatusStream.listen((data) {
      setState(() {
        _agentActivities.add({
          'icon': _getStatusIcon(data['status']),
          'message': data['message'],
          'timestamp': DateTime.now(),
        });
        _agentStatus = data['status'];
        _isAgentRunning = data['status'] != 'completed' && data['status'] != 'error' && data['status'] != 'cancelled';
        if ((data['status'] == 'error' || data['status'] == 'cancelled') && _isGrowthLoading) {
          _isGrowthLoading = false;
          _growthError ??= 'Growth search stopped. Try again.';
        }
      });
    });

    // Listen to browser actions
    _chatService.browserActionStream.listen((data) {
      setState(() {
        _agentActivities.add({
          'icon': data['action'] == 'start_browser'
              ? Icons.web
              : data['action'] == 'open_source'
                  ? Icons.open_in_new
                  : Icons.travel_explore,
          'message': data['message'],
          'timestamp': DateTime.now(),
          'url': data['url'],
        });
      });
    });

    // Listen to found products
    _chatService.productFoundStream.listen((data) {
      setState(() {
        _foundProducts.add(data['product']);
      });
    });

    // Listen to final results
    _chatService.finalResultStream.listen((data) {
      setState(() {
        _recommendations = List<Map<String, dynamic>>.from(data['recommendations']);
        _isAgentRunning = false;
      });
    });

    // Capture the task_id when the agent starts so STOP works
    _chatService.commerceStartedStream.listen((data) {
      print('Commerce started event: $data');
      setState(() {
        _currentTaskId = data['task_id'];
      });
    });

    // Listen to errors
    _chatService.commerceErrorStream.listen((data) {
      setState(() {
        _agentActivities.add({
          'icon': Icons.error,
          'message': data['message'],
          'timestamp': DateTime.now(),
          'isError': true,
        });
        _isAgentRunning = false;
        if (_isGrowthLoading) {
          _isGrowthLoading = false;
          _growthError = data['message'] ?? 'The growth search failed. Please try again.';
        }
      });
    });

    // Listen to cancellation
    _chatService.commerceCancelledStream.listen((data) {
      setState(() {
        _agentActivities.add({
          'icon': Icons.cancel,
          'message': data['message'],
          'timestamp': DateTime.now(),
        });
        _isAgentRunning = false;
      });
    });

    // Confirmation gate: a product was selected, awaiting explicit confirmation
    _chatService.confirmationRequiredStream.listen((data) {
      setState(() {
        _pendingConfirmation = data;
      });
    });

    // Selection confirmed -> bounded action completed
    _chatService.selectionConfirmedStream.listen((data) {
      setState(() {
        _agentActivities.add({
          'icon': Icons.verified_user,
          'message': data['note'] ?? 'Selection confirmed',
          'timestamp': DateTime.now(),
        });
        _pendingConfirmation = null;
      });
    });

    // Comparison result
    _chatService.comparisonStream.listen((data) {
      setState(() {
        _comparisonData = data;
        _growthProducts = [];
        _growthTitle = '';
      });
    });

    // Cross-sell / upsell result
    _chatService.growthResultStream.listen((data) {
      setState(() {
        final products = List<Map<String, dynamic>>.from(data['products'] ?? []);
        _growthProducts = products;
        _isGrowthLoading = false;
        if (products.isNotEmpty) {
          _growthError = null;
        }
        _growthTitle = data['growth_type'] == 'cross_sell'
            ? 'Compatible accessories'
            : data['growth_type'] == 'upsell'
                ? 'Better alternatives'
                : 'Related options';
        _comparisonData = null;
        _isAgentRunning = false;
        if (data['message'] != null) {
          _agentActivities.add({
            'icon': data['growth_type'] == 'cross_sell' ? Icons.add_shopping_cart : Icons.trending_up,
            'message': data['message'],
            'timestamp': DateTime.now(),
          });
        }
      });
    });

    // ---- Phase 4 checkout / payment streams ----

    // Checkout ready = the approval gate. Show the order summary and require the
    // user to explicitly approve before any payment is created.
    _chatService.checkoutReadyStream.listen((data) {
      setState(() {
        _checkoutReady = data;
        _paymentInitiated = null;
        _paymentResult = null;
        _agentActivities.add({
          'icon': Icons.shopping_cart_checkout,
          'message': 'Checkout preview ready for: ${(data['product'] as Map<String, dynamic>? ?? {})['name']}',
          'timestamp': DateTime.now(),
        });
      });
    });

    // Checkout blocked = the policy guard refused the purchase. The agent will
    // NOT create an order or payment. Show the reason to the user.
    _chatService.checkoutBlockedStream.listen((data) {
      setState(() {
        _checkoutBlocked = data;
        _checkoutReady = null;
        _paymentInitiated = null;
        _paymentResult = null;
        _agentActivities.add({
          'icon': Icons.block,
          'message': 'Purchase blocked: ${data['reason'] ?? 'violates user policy'}',
          'timestamp': DateTime.now(),
          'isError': true,
        });
      });
    });

    // Order created + payment initiated: a Razorpay (test) order now exists.
    _chatService.paymentInitiatedStream.listen((data) {
      setState(() {
        _paymentInitiated = data;
        _agentActivities.add({
          'icon': Icons.account_balance_wallet,
          'message': 'Razorpay ${data['test_mode'] == true ? 'test' : ''} order created (₹${data['amount']}). Awaiting payment.',
          'timestamp': DateTime.now(),
        });
      });
    });

    _chatService.paymentSuccessStream.listen((data) {
      setState(() {
        _paymentResult = data;
        _isPaymentSuccess = true;
        _lastOrderId = data['order_id'];
        _checkoutReady = null;
        _paymentInitiated = null;
        _agentActivities.add({
          'icon': Icons.check_circle,
          'message': data['message'] ?? 'Payment successful',
          'timestamp': DateTime.now(),
        });
      });
    });

    _chatService.paymentFailedStream.listen((data) {
      setState(() {
        _paymentResult = data;
        _isPaymentSuccess = false;
        _lastOrderId = data['order_id'];
        // On failure we keep the gate so the user can retry.
        _paymentInitiated = null;
        _agentActivities.add({
          'icon': Icons.error_outline,
          'message': data['reason'] ?? 'Payment failed',
          'timestamp': DateTime.now(),
          'isError': true,
        });
      });
    });
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'starting':
        return Icons.play_circle_outline;
      case 'analyzing':
        return Icons.psychology;
      case 'planning':
        return Icons.event_note;
      case 'browsing':
        return Icons.web;
      case 'extracting':
        return Icons.content_copy;
      case 'comparing':
        return Icons.compare;
      case 'recommending':
        return Icons.star;
      case 'completed':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  void _startAgent() {
    if (_queryController.text.trim().isEmpty) return;
    
    setState(() {
      _agentActivities = [];
      _foundProducts = [];
      _recommendations = [];
      _isAgentRunning = true;
      _currentTaskId = null;
      _selectedIndex = null;
      _pendingConfirmation = null;
      _comparisonData = null;
      _growthProducts = [];
      _growthTitle = '';
      _checkoutReady = null;
      _checkoutBlocked = null;
      _paymentInitiated = null;
      _paymentResult = null;
      _isPaymentSuccess = false;
      _lastOrderId = null;
    });

    _chatService.startCommerceAgent(_queryController.text.trim());
  }

  void _stopAgent() {
    if (_currentTaskId != null) {
      _chatService.cancelCommerceAgent(_currentTaskId!);
    } else {
      print('No task id to cancel');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent is still starting, try again in a moment.')),
      );
    }
  }

  void _selectProduct(int index) {
    if (_currentTaskId == null) return;
    _chatService.selectCommerceProduct(_currentTaskId!, index);
  }

  void _confirmSelection() {
    if (_currentTaskId == null) return;
    _chatService.confirmCommerceSelection(_currentTaskId!);
  }

  void _compareProducts(List<int> indexes) {
    if (_currentTaskId == null) return;
    _chatService.compareCommerceProducts(_currentTaskId!, indexes);
  }

  void _crossSell(int index) {
    if (_currentTaskId == null) return;
    setState(() {
      _isGrowthLoading = true;
      _growthError = null;
      _growthProducts = [];
      _growthTitle = 'Searching for compatible accessories...';
      _comparisonData = null;
    });
    _chatService.crossSellCommerce(_currentTaskId!, index);
  }

  void _upsell(int index) {
    if (_currentTaskId == null) return;
    setState(() {
      _isGrowthLoading = true;
      _growthError = null;
      _growthProducts = [];
      _growthTitle = 'Searching for a better alternative...';
      _comparisonData = null;
    });
    _chatService.upsellCommerce(_currentTaskId!, index);
  }

  // ---- Phase 4 checkout / payment actions ----

  void _startCheckout(int index) {
    if (_currentTaskId == null) return;
    setState(() {
      // clear prior checkout state for a fresh gate
      _checkoutReady = null;
      _checkoutBlocked = null;
      _paymentInitiated = null;
      _paymentResult = null;
    });
    _chatService.checkoutCommerce(_currentTaskId!, index);
  }

  void _dismissCheckoutBlocked() {
    setState(() {
      _checkoutBlocked = null;
    });
  }

  void _approveAndPay() {
    if (_currentTaskId == null) return;
    _chatService.approveCommercePayment(_currentTaskId!);
  }

  // Demo-mode payment simulation: the backend maps pay_demo_success / pay_demo_fail.
  void _simulatePayment(bool success) {
    if (_currentTaskId == null) return;
    _chatService.confirmCommercePayment(
      _currentTaskId!,
      success ? 'pay_demo_success' : 'pay_demo_fail',
    );
  }

  // Production-type flow: launch the real Razorpay hosted Checkout (test mode)
  // using the order the backend created. Razorpay hands back the payment id and
  // signature, which we forward to the backend for server-side verification.
  Future<void> _openRazorpayCheckout() async {
    final initiated = _paymentInitiated;
    final keyId = (initiated?['key_id'] as String?) ?? '';
    final orderId = (initiated?['razorpay_order_id'] as String?) ?? '';
    final amount = (initiated?['amount'] as num?)?.toDouble() ?? 0;
    final currency = (initiated?['currency'] as String?) ?? 'INR';
    if (keyId.isEmpty || orderId.isEmpty) {
      _showSnack('Razorpay order not ready. Please Approve & Pay first.');
      return;
    }

    setState(() {
      _agentActivities.add({
        'icon': Icons.account_balance_wallet,
        'message': 'Razorpay Checkout opened — awaiting payment.',
        'timestamp': DateTime.now(),
      });
    });

    try {
      await RazorpayCheckout.open(
        keyId: keyId,
        orderId: orderId,
        amountPaise: (amount * 100).round(),
        currency: currency,
        name: 'Waflo AI Commerce',
        description: 'Product order for ${(_checkoutReady?['product'] as Map<String, dynamic>? ?? {})['name'] ?? 'item'}',
        onSuccess: (result) {
          if (!mounted) return;
          if (result.paymentId.isEmpty) {
            _showSnack('Payment could not be confirmed (missing payment id).');
            return;
          }
          _agentActivities.add({
            'icon': Icons.account_balance_wallet,
            'message': 'Payment received — verifying with backend.',
            'timestamp': DateTime.now(),
          });
          if (_currentTaskId != null) {
            _chatService.confirmCommercePayment(
              _currentTaskId!,
              result.paymentId,
              signature: result.signature,
            );
          }
        },
        onFailure: (message) {
          if (!mounted) return;
          setState(() {
            _agentActivities.add({
              'icon': Icons.info_outline,
              'message': 'Razorpay checkout closed: $message',
              'timestamp': DateTime.now(),
            });
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not open Razorpay checkout: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retryPayment() {
    setState(() {
      _paymentResult = null;
      _paymentInitiated = null;
    });
    // Re-approve to create a fresh Razorpay order, staying gated.
    if (_currentTaskId != null) {
      _chatService.approveCommercePayment(_currentTaskId!);
    }
  }

  void _cancelCheckout() {
    setState(() {
      _checkoutReady = null;
      _paymentInitiated = null;
      _paymentResult = null;
    });
    if (_currentTaskId != null) {
      _chatService.cancelCommerceCheckout(_currentTaskId!);
    }
  }

  void _handleNavigation(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  Future<void> _launchWebUI() async {
    final Uri webUiUrl = Uri.parse('http://127.0.0.1:7788');
    if (!await launchUrl(webUiUrl, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch web-ui')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          sidebar(onNavigate: _handleNavigation, selectedIndex: 1),
          
          // Main content
          Expanded(
            child: Column(
              children: [
                // Commerce Controls
                CommerceControls(
                  queryController: _queryController,
                  isAgentRunning: _isAgentRunning,
                  onStartAgent: _startAgent,
                  onStopAgent: _stopAgent,
                ),
                
                // Agent Activity Timeline
                Expanded(
                  child: CommerceAgentTimeline(
                    activities: _agentActivities,
                  ),
                ),

                // Result panels below the timeline stack as flexible, scrollable
                // content so many panels never overflow the viewport.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                // Confirmation Gate Panel
                if (_pendingConfirmation != null)
                  _buildConfirmationPanel(),

                // Comparison Panel
                if (_comparisonData != null)
                  _buildComparisonPanel(),

                // Phase 4: Checkout approval gate
                if (_checkoutReady != null)
                  _buildCheckoutPanel(),

                // Phase 6: Policy guard rejection
                if (_checkoutBlocked != null)
                  _buildCheckoutBlockedPanel(),

                // Phase 4: Payment result (success / failure with retry)
                if (_paymentResult != null)
                  _buildPaymentResultPanel(),

                // Growth Products (cross-sell / upsell)
                if (_isGrowthLoading || _growthProducts.isNotEmpty || _growthError != null)
                  Container(
                    height: 210,
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _growthTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Expanded(
                          child: _isGrowthLoading
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: Colors.blue[300]),
                                      SizedBox(height: 12),
                                      Text(
                                        'Agent searching live for products...',
                                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : _growthError != null && _growthProducts.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.search_off, color: Colors.orange[300], size: 32),
                                            SizedBox(height: 8),
                                            Text(
                                              _growthError!,
                                              style: TextStyle(color: Colors.orange[200], fontSize: 13),
                                              textAlign: TextAlign.center,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Tip: click the same button again to retry.',
                                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : _growthProducts.isEmpty
                                      ? Center(
                                          child: Text(
                                            'No matches found for this search. Try again or pick another product.',
                                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _growthProducts.length,
                                          itemBuilder: (context, index) {
                                            return CommerceProductCard(
                                              product: _growthProducts[index],
                                            );
                                          },
                                        ),
                        ),
                      ],
                    ),
                  ),

                // Found Products Section
                if (_foundProducts.isNotEmpty)
                  Container(
                    height: 200,
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Found Products (${_foundProducts.length})',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _foundProducts.length,
                            itemBuilder: (context, index) {
                              return CommerceProductCard(
                                product: _foundProducts[index],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // Recommendations Section
                if (_recommendations.isNotEmpty)
                  Container(
                    height: 360,
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Top Recommendations',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            // Compare action across top picks
                            if (_recommendations.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _compareProducts(
                                    [for (var i = 0; i < _recommendations.length && i < 2; i++) i]),
                                icon: Icon(Icons.compare_arrows, size: 18),
                                label: Text('Compare top 2'),
                                style: TextButton.styleFrom(foregroundColor: Colors.blue[300]),
                              ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _recommendations.length,
                            itemBuilder: (context, index) {
                              final isSelected = _selectedIndex == index;
                              return Column(
                                children: [
                                  Expanded(
                                    child: CommerceProductCard(
                                      product: _recommendations[index]['product'],
                                      score: _recommendations[index]['score'],
                                      reasoning: _recommendations[index]['reasoning'] == null
                                          ? null
                                          : List<String>.from(_recommendations[index]['reasoning'] as List),
                                    ),
                                  ),
                                  // Action buttons for the recommendation
                                  Container(
                                    width: 280,
                                    margin: EdgeInsets.only(right: 12, top: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _selectProduct(index),
                                            icon: Icon(Icons.check, size: 16),
                                            label: Text(isSelected ? 'Selected' : 'Select'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: isSelected ? Colors.green : Colors.blue[300],
                                              side: BorderSide(color: isSelected ? Colors.green : Colors.blue[300]!),
                                              padding: EdgeInsets.symmetric(vertical: 4),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        IconButton(
                                          onPressed: () => _crossSell(index),
                                          icon: Icon(Icons.add_shopping_cart, size: 18),
                                          tooltip: 'Find accessories',
                                          color: Colors.orange[300],
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        IconButton(
                                          onPressed: () => _upsell(index),
                                          icon: Icon(Icons.trending_up, size: 18),
                                          tooltip: 'Find better alternative',
                                          color: Colors.purple[300],
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Phase 4: "Buy now" -> gated checkout
                                  Container(
                                    width: 280,
                                    margin: EdgeInsets.only(right: 12, top: 6),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _startCheckout(index),
                                      icon: Icon(Icons.shopping_cart_checkout, size: 18),
                                      label: Text('Buy now'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationPanel() {
    final product = _pendingConfirmation!['product'] as Map<String, dynamic>;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirm your selection',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            product['name'] ?? 'Selected product',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (product['price'] != null)
            Text(
              'Amount: ₹${product['price']}',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          if (_pendingConfirmation!['action_description'] != null)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                _pendingConfirmation!['action_description'].toString(),
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
            ),
          SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _confirmSelection,
                icon: Icon(Icons.check, size: 18),
                label: Text('Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
              ),
              SizedBox(width: 10),
              TextButton(
                onPressed: () => setState(() {
                  _pendingConfirmation = null;
                }),
                child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonPanel() {
    final lines = (_comparisonData!['comparison_lines'] as List<dynamic>? ?? []);
    final verdict = _comparisonData!['verdict'] as String? ?? '';
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text(
                'Product Comparison',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          if (lines.isNotEmpty)
            ...lines.map((line) {
              final name = line['attribute'].toString();
              final values = (line['values'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList();
              return Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        name,
                        style: TextStyle(
                          color: Colors.blue[200],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        values.join('  |  '),
                        style: TextStyle(color: Colors.grey[200], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (verdict.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  verdict,
                  style: TextStyle(color: Colors.blue[100], fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBlockedPanel() {
    final data = _checkoutBlocked!;
    final product = data['product'] as Map<String, dynamic>? ?? {};
    final amount = data['amount'];
    final maxBudget = data['max_budget'];
    final reason = data['reason']?.toString() ?? 'This purchase violates your set policy.';

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Purchase blocked — policy guard',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            product['name'] ?? 'Product',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (amount != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Cost: ₹$amount',
                style: TextStyle(color: Colors.red[200], fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          if (maxBudget != null)
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Your budget: ₹$maxBudget',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              reason,
              style: TextStyle(color: Colors.red[100], fontSize: 13),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'No order or payment was created.',
            style: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _dismissCheckoutBlocked,
                icon: Icon(Icons.close, size: 18),
                label: Text('Got it'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[300],
                  side: BorderSide(color: Colors.grey[600]!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutPanel() {
    final product = _checkoutReady!['product'] as Map<String, dynamic>? ?? {};
    final amount = _checkoutReady!['amount'] ?? 0;
    final actionDescription = _checkoutReady!['action_description']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart_checkout, color: Colors.teal, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checkout preview',
                  style: TextStyle(
                    color: Colors.teal,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            product['name'] ?? 'Product',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (product['price'] != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Price: ₹${product['price']}',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Total: ₹$amount',
              style: TextStyle(color: Colors.teal[200], fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (actionDescription.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                actionDescription,
                style: TextStyle(color: Colors.grey[350], fontSize: 12),
              ),
            ),
          SizedBox(height: 14),
          Row(
            children: [
              // Explicit, bounded approval. Never auto-pays.
              ElevatedButton.icon(
                onPressed: _approveAndPay,
                icon: Icon(Icons.verified_user, size: 18),
                label: Text('Approve & Pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              TextButton(
                onPressed: _cancelCheckout,
                child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
              ),
            ],
          ),
          if (_paymentInitiated != null) ...[
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Razorpay ${_paymentInitiated!['test_mode'] == true ? 'test' : ''} order created',
                    style: TextStyle(color: Colors.blue[200], fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (_paymentInitiated!['razorpay_order_id'] != null)
                    Text(
                      'Order id: ${_paymentInitiated!['razorpay_order_id']}',
                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                    ),
                  SizedBox(height: 8),
                  // Primary path: real Razorpay hosted Checkout (test mode) when
                  // a key id is available. This is the merchant checkout the user
                  // actually completes (bounded + gated on the backend).
                  if ((_paymentInitiated!['key_id'] as String?)?.isNotEmpty == true) ...[
                    ElevatedButton.icon(
                      onPressed: _openRazorpayCheckout,
                      icon: Icon(Icons.payment, size: 18),
                      label: Text('Open Razorpay Checkout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'You will complete this test payment through Razorpay\u2019s hosted checkout (no real money involved).',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ] else ...[
                    // Demo-mode payment simulation for a self-contained
                    // buildathon demo when no live checkout SDK is configured.
                    Text(
                      'Test payment (no real money):',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _simulatePayment(true),
                          icon: Icon(Icons.check_circle, size: 16),
                          label: Text('Simulate Success'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: BorderSide(color: Colors.green),
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _simulatePayment(false),
                          icon: Icon(Icons.cancel, size: 16),
                          label: Text('Simulate Failure'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red),
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentResultPanel() {
    final result = _paymentResult!;
    final orderId = result['order_id'] ?? _lastOrderId;
    final amount = result['amount'];

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (_isPaymentSuccess ? Colors.green : Colors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (_isPaymentSuccess ? Colors.green : Colors.red).withOpacity(0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isPaymentSuccess ? Icons.check_circle : Icons.error_outline,
                color: _isPaymentSuccess ? Colors.green : Colors.red,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                _isPaymentSuccess ? 'Payment successful' : 'Payment failed',
                style: TextStyle(
                  color: _isPaymentSuccess ? Colors.green : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (orderId != null) ...[
            SizedBox(height: 8),
            Text(
              'Order: $orderId',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
          if (amount != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Amount: ₹$amount',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
          if (result['razorpay_payment_id'] != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Payment id: ${result['razorpay_payment_id']}',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
            ),
          if (!_isPaymentSuccess &&
              (result['reason'] != null || result['message'] != null))
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                (result['reason'] ?? result['message']).toString(),
                style: TextStyle(color: Colors.red[100], fontSize: 12),
              ),
            ),
          if (!_isPaymentSuccess) ...[
            SizedBox(height: 12),
            Row(
              children: [
                // Graceful failure handling: let the user retry (still gated).
                ElevatedButton.icon(
                  onPressed: _retryPayment,
                  icon: Icon(Icons.refresh, size: 18),
                  label: Text('Retry payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                SizedBox(width: 10),
                TextButton(
                  onPressed: _cancelCheckout,
                  child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
                ),
              ],
            ),
          ],
          if (_isPaymentSuccess) ...[
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Purchase complete. The full decision + payment trail is recorded in the audit log.',
                style: TextStyle(color: Colors.green[100], fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }
}