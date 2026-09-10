import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/widgets/strobi_assistant_message.dart';
import 'package:skeletonizer/skeletonizer.dart';

class AnswerSection extends StatefulWidget {
  const AnswerSection({super.key});

  @override
  State<AnswerSection> createState() => _AnswerSectionState();
}

class _AnswerSectionState extends State<AnswerSection> {
  bool isLoading = true;

  // Store the stream listener
  StreamSubscription? _subscription;
  StreamSubscription<Map<String, dynamic>>? _doneSub;

  // When true, this widget is rendering a live assistant answer which should
  // be persisted to the active conversation once the backend signals `done`.
  bool _persistTurn = false;

  String fullResponse = '''
As of the end of Day 1 in the fourth Test match between India and Australia, the score stands at **Australia 311/6**. The match is being held at the Melbourne Cricket Ground (MCG) on December 26, 2024.

## Match Overview
- **Toss**: Australia won the toss and opted to bat first.
- **Top Performers**:
  - **Steve Smith** is currently unbeaten on **68 runs** from **111 balls**.
  - **Sam Konstas**, making his Test debut, scored a significant **60 runs** from **65 balls**.

## Current Situation
As play concluded for the day, Australia stood at **311/6**.
''';

  static const String _fallbackSentinel = '__FALLBACK__';
  static const String _friendlyFallbackMessage =
      "I couldn't reach the AI model just now — it's temporarily at its rate limit. "
      "Please wait about a minute and try asking again.";

  // True when the response received from the backend was the fallback sentinel.
  // Such a turn must never be shown raw nor persisted.
  bool _showingFallback = false;

  @override
  void initState() {
    super.initState();

    _subscription =
        ChatWebService().contentStream.listen((data) {
      // Important: don't call setState if widget is already removed
      if (!mounted) return;

      // Clear the old/default response when the first new chunk arrives
      if (isLoading) {
        fullResponse = "";
        _showingFallback = false;
        _persistTurn = true;
      }

      setState(() {
        final chunk = data['data'] ?? '';
        final raw = fullResponse + chunk;
        if (raw.trim().contains(_fallbackSentinel)) {
          fullResponse = _friendlyFallbackMessage;
          _showingFallback = true;
          _persistTurn = false;
        } else {
          fullResponse = raw;
        }
        isLoading = false;
      });
    });

    _doneSub = ChatWebService().realtimeStream.listen((data) {
      // Persist the completed assistant answer once, for this turn only.
      if (data['type'] != 'done' || !_persistTurn) return;
      _persistTurn = false;
      final answer = fullResponse.trim();
      if (mounted && answer.isNotEmpty && !_showingFallback) {
        unawaited(
          ChatHistoryController.instance.saveAssistantMessage(answer),
        );
      }
    });
  }

  @override
  void dispose() {
    // Stop listening to the stream when this widget is destroyed
    _subscription?.cancel();
    _doneSub?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),

        const Text(
          'WAFLO',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        Skeletonizer(
          enabled: isLoading,

          child: Markdown(
            data: fullResponse,
            shrinkWrap: true,
            styleSheet: strobiMarkdownStyle(context),
          ),
        ),
        if (!isLoading && fullResponse.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: fullResponse));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard!')),
                );
              },
              icon: const Icon(Icons.copy, color: Colors.grey, size: 16),
              label: const Text('Copy', style: TextStyle(color: Colors.grey)),
            ),
          ),
      ],
    );
  }
}