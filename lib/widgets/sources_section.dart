import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';

class SourcesSection extends StatefulWidget {
  const SourcesSection({super.key});

  @override
  State<SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<SourcesSection> {
  bool isLoading = true;

  List searchResults = [];

  // Store the stream subscription
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        ChatWebService().searchResultStream.listen((data) {
      // Do not call setState after widget is destroyed
      if (!mounted) return;

      setState(() {
        searchResults = data['data'] ?? [];
        isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    // Cancel the listener when this widget is removed
    _subscription?.cancel();

    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch URL')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.source_outlined,
              color: Colors.white,
            ),

            const SizedBox(width: 8),

            const Text(
              "Sources",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )

            ),

          ],
        ),

        const SizedBox(height: 16),

        Skeletonizer(
          enabled: isLoading,

          child: Wrap(
            spacing: 16,
            runSpacing: 16,

            children: searchResults.map((res) {
              return GestureDetector(
                onTap: () => _launchUrl(res['url'] ?? ''),
                child: Container(
                  width: 150,

                  padding: const EdgeInsets.all(16),

                  decoration: BoxDecoration(
                    color: AppColors.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),

                  child: Column(
                    children: [
                      Text(
                        res['title'] ?? '',

                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),

                        maxLines: 2,

                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 8),

                      Text(
                        res['url'] ?? '',

                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}