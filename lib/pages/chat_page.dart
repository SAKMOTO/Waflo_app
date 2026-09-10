import 'package:flutter/material.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/widgets/answer_section.dart';
import 'package:waflo_app/widgets/strobi_assistant_message.dart';
import 'package:waflo_app/widgets/chat_history_sidebar.dart';
import 'package:waflo_app/widgets/side_bar.dart';
import 'package:waflo_app/widgets/sources_section.dart';
import 'dart:convert';
import 'package:waflo_app/models/chat_message_model.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/pages/main_page.dart';
import 'package:waflo_app/widgets/chat_input_bar.dart';
import 'package:waflo_app/widgets/image_gallery.dart';
import 'package:waflo_app/services/chat_web_service.dart';

/// Renders a single chat: the live search/answer flow for the current
/// [question] (as before) plus, when [conversationId] is supplied, the saved
/// history of that conversation above it. Opening a history chat shows only
/// the stored messages; sending a new message continues that conversation.
class ChatPage extends StatefulWidget {
  final String? question;
  final String? conversationId;

  const ChatPage({super.key, this.question, this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<ChatMessageModel> _history = const [];
  bool _loadingHistory = false;

  /// Chat History panel beside the sidebar on this page.
  bool _historyOpen = false;

  void _toggleHistory() {
    setState(() => _historyOpen = !_historyOpen);
  }

  @override
  void initState() {
    super.initState();
    final conversationId = widget.conversationId;
    if (conversationId != null && conversationId.isNotEmpty) {
      _loadHistory(conversationId);
    }
  }

  Future<void> _loadHistory(String conversationId) async {
    setState(() => _loadingHistory = true);
    final controller = ChatHistoryController.instance;
    await controller.openConversation(conversationId);
    if (!mounted) return;
    setState(() {
      _history = List.of(controller.messages);
      _loadingHistory = false;
    });
  }

  /// Home is the page beneath the chat route (chat is always pushed on top),
  /// so popping back preserves this screen's state while returning to Home.
  void _goHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/home');
    }
  }

  void _handleNavigation(int index) {
    if (index == 0) {
      _goHome();
    } else if (index == 1) {
      Navigator.of(context).pushNamed('/commerce');
    }
  }

  void _handleMainNavigation() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Scaffold(
      body: Row(
        children: [
          sidebar(
            onNavigate: _handleNavigation,
            onNavigateMain: _handleMainNavigation,
            onNavigateBuilder: () => Navigator.pushNamed(context, '/builder'),
            chatHistoryExpanded: _historyOpen,
            onChatHistoryToggle: _toggleHistory,
          ),
          ChatHistorySidebar(open: _historyOpen, onToggle: _toggleHistory),
          Expanded(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TextButton.icon(
                      onPressed: _goHome,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back to Home'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadingHistory)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_history.isNotEmpty) ...[
                          for (final message in _history)
                            _buildHistoryMessage(message),
                          const SizedBox(height: 24),
                        ],
                        if (question != null && question.isNotEmpty) ...[
                          Text(
                            question,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const SourcesSection(),
                          StreamBuilder<List<String>>(
                            stream: ChatWebService().imagesStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data!.isNotEmpty) {
                                return ImageGallery(imageUrls: snapshot.data!);
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          StreamBuilder<String>(
                            stream: ChatWebService().generatedImageStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 20.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.memory(
                                      base64Decode(snapshot.data!),
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          const AnswerSection(),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 16.0),
                  child: ChatInputBar(replacePage: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryMessage(ChatMessageModel message) {
    if (message.role == 'user') {
      return _UserBubble(text: message.content);
    }
    if (message.role == 'assistant') {
      return StrobiAssistantMessage(
        text: message.content,
        accent: AppColors.submitButton,
      );
    }
    // System/unknown roles render as plain assistant text.
    return const SizedBox.shrink();
  }
}

class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.6,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.submitButton,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.background,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}