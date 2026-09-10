import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:waflo_app/agents/agent_type.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/controllers/chat_history_controller.dart';
import 'package:waflo_app/pages/agent_workspace_page.dart';
import 'package:waflo_app/pages/chat_page.dart';
import 'package:waflo_app/pages/commerce_page.dart';
import 'package:waflo_app/theme/colors.dart';
import 'package:waflo_app/services/chat_web_service.dart';
import 'package:waflo_app/widgets/avatar_selector.dart';
import 'package:waflo_app/widgets/morph_hint.dart';

class ChatInputBar extends StatefulWidget {
  final bool replacePage;
  final bool showBrowserToggle;

  /// Fired with `true` while the user is typing in the search box (used to
  /// trigger the bloub avatar's left-right eye movement).
  final ValueChanged<bool>? onTypingChanged;

  /// Small reactive AI companion positioned at the top-left edge of the input
  /// bar. Placed inside a [Stack] so it stays anchored to the bar regardless
  /// of where the bar sits on the page.
  final Widget? avatar;

  const ChatInputBar({
    super.key,
    this.replacePage = false,
    this.showBrowserToggle = false,
    this.onTypingChanged,
    this.avatar,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final queryController = TextEditingController();
  String? selectedFileName;
  String? selectedFileBase64;
  bool browserAgent = false;
  bool _isLoading = false;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = ChatWebService().realtimeStream.listen((data) {
      if (!mounted) return;
      bool next;
      switch (data['type']) {
        case 'search_result':
        case 'browse_started':
          next = true;
          break;
        case 'done':
        case 'error':
        case 'browse_cancelled':
          next = false;
          break;
        default:
          return;
      }
      if (next != _isLoading) setState(() => _isLoading = next);
    });
  }

  Future<void> pickFile() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      List<int> fileBytes = await file.readAsBytes();
      setState(() {
        selectedFileName = result.files.single.name;
        selectedFileBase64 = base64Encode(fileBytes);
      });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
    queryController.dispose();
  }

  void _submit() {
    if (queryController.text.trim().isEmpty && selectedFileName == null) return;

    final queryText = queryController.text.trim();

    // Browser Agent toggle is ON -> run the selected character's agent live
    // (the toggle label reflects whichever agent the character maps to).
    if (browserAgent) {
      final characterId =
          AvatarController.instance.currentCharacter?.id ?? 'strobi';
      final agent = agentIdentityForCharacter(characterId);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              AgentWorkspacePage(agent: agent, initialTask: queryText),
        ),
      );
      return;
    }

    final isCommerceQuery =
        queryText.toLowerCase().contains('find') ||
        queryText.toLowerCase().contains('buy') ||
        queryText.toLowerCase().contains('shop');

    if (isCommerceQuery) {
      if (widget.replacePage) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CommercePage(initialQuery: queryText),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CommercePage(initialQuery: queryText),
          ),
        );
      }
      return;
    }

    // Only send generic chat event if it's not a commerce query
    ChatWebService().chat(
      queryText,
      fileName: selectedFileName,
      fileBase64: selectedFileBase64,
    );

    // Persist the user turn. Starting from the home bar begins a NEW thread;
    // from inside a chat it continues the active conversation. The assistant
    // reply is saved by AnswerSection once the backend emits `done`.
    final history = ChatHistoryController.instance;
    if (!widget.replacePage) {
      unawaited(history.startNewChat());
    }
    unawaited(history.saveUserMessage(queryText));

    if (widget.replacePage) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ChatPage(
            question: queryText,
            conversationId: ChatHistoryController.instance.activeConversationId,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ChatPage(question: queryText)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 700,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
                child: _isLoading
                    ? Padding(
                        key: const ValueKey('loading'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Lottie.asset(
                          'assets/loading.json',
                          width: 56,
                          height: 56,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
              ),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.searchBar,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: AppColors.searchBarBorder),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: queryController,
                              builder: (context, value, _) {
                                const hintStyle = TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                );
                                return Stack(
                                  children: [
                                    if (value.text.isEmpty)
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: MorphHint(
                                            phrases: const [
                                              'Search anything',
                                              'What do you want to know?',
                                              'Ask anything',
                                            ],
                                            style: hintStyle,
                                          ),
                                        ),
                                      ),
                                    TextField(
                                      controller: queryController,
                                      style: hintStyle,
                                      decoration: InputDecoration(
                                        hintStyle: hintStyle,
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onSubmitted: (_) => _submit(),
                                      onChanged: (value) {
                                        widget.onTypingChanged?.call(value.isNotEmpty);
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          const AvatarSelector(),
                        ],
                      ),
                    ),
                    if (selectedFileName != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.attach_file,
                              color: Colors.grey,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              selectedFileName!,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 16,
                              ),
                              onPressed: () {
                                setState(() {
                                  selectedFileName = null;
                                  selectedFileBase64 = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.auto_awesome, size: 20),
                            onPressed: () {},
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.add_circle_outline, size: 20),
                            onPressed: pickFile,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                          if (widget.showBrowserToggle)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Tooltip(
                                message: browserAgent
                                    ? 'Browser Agent: ON'
                                    : 'Browser Agent: OFF',
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => browserAgent = !browserAgent,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: browserAgent
                                          ? const Color(0x2634C77B)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      browserAgent
                                          ? Icons.bolt
                                          : Icons.bolt_outlined,
                                      size: 18,
                                      color: browserAgent
                                          ? const Color(0xFF34C77B)
                                          : AppColors.iconGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Spacer(),
                          GestureDetector(
                            onTap: _submit,
                            child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.submitButton,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                color: AppColors.background,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.avatar != null)
            Positioned(
              left: -16,
              top: -58,
              child: IgnorePointer(child: widget.avatar),
            ),
        ],
      ),
    );
  }
}