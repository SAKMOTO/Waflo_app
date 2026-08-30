import 'package:flutter/material.dart';

class CommerceProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final double? score;
  final List<String>? reasoning;

  const CommerceProductCard({
    super.key,
    required this.product,
    this.score,
    this.reasoning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: EdgeInsets.only(right: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: score != null ? Colors.green.withOpacity(0.3) : Colors.grey[700]!,
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
          // Product Name
          Text(
            product['name'] ?? 'Unknown Product',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          
          // Price
          if (product['price'] != null)
            Text(
              '₹${product['price']}',
              style: TextStyle(
                color: Colors.green,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (product['price'] == null)
            Text(
              'Price not available',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          SizedBox(height: 8),
          
          // Features
          if (product['features'] != null && (product['features'] as List).isNotEmpty)
            ...((product['features'] as List).take(3).map((feature) => Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 12,
                    color: Colors.green,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      feature.toString(),
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ))),
          
          // Rating
          if (product['rating'] != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.star, size: 14, color: Colors.yellow),
                  SizedBox(width: 4),
                  Text(
                    product['rating'].toString(),
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          
          // Availability
          if (product['availability'] != null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                product['availability'].toString(),
                style: TextStyle(
                  color: product['availability'] == 'In Stock' 
                      ? Colors.green 
                      : Colors.red,
                  fontSize: 12,
                ),
              ),
            ),
          
          // Score (for recommendations)
          if (score != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Match Score: ${score!.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          
          // Reasoning (for recommendations)
          if (reasoning != null && reasoning!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why recommended:',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  ...reasoning!.take(2).map((reason) => Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(
                      reason,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                ],
              ),
            ),
          
          // Source URL
          if (product['source_url'] != null)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Source: ${_getDomain(product['source_url'])}',
                style: TextStyle(
                  color: Colors.blue[300],
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return 'Unknown';
    }
  }
}