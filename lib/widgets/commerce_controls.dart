import 'package:flutter/material.dart';

class CommerceControls extends StatelessWidget {
  final TextEditingController queryController;
  final bool isAgentRunning;
  final VoidCallback onStartAgent;
  final VoidCallback onStopAgent;

  const CommerceControls({
    super.key,
    required this.queryController,
    required this.isAgentRunning,
    required this.onStartAgent,
    required this.onStopAgent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.shopping_cart,
                color: Colors.blue,
                size: 24,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI Shopping Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAgentRunning)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Active',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          
          // Query Input
          TextField(
            controller: queryController,
            enabled: !isAgentRunning,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Describe what you want to buy, e.g. "a 65W GaN charger under ₹2000"',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[700]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            maxLines: 2,
          ),
          SizedBox(height: 12),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isAgentRunning ? null : onStartAgent,
                  icon: Icon(isAgentRunning ? Icons.hourglass_empty : Icons.search),
                  label: Text(isAgentRunning ? 'Searching...' : 'Start Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAgentRunning ? Colors.grey : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              if (isAgentRunning)
                ElevatedButton.icon(
                  onPressed: onStopAgent,
                  icon: Icon(Icons.stop),
                  label: Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
          
          // Help Text
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Tip: Mention budget, features or use case. Compare top picks, then Buy now to check out securely with Razorpay.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}