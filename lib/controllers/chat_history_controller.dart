import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import '../services/chat_history_service.dart';
import '../services/supabase_service.dart';

/// App-wide state for persisted chat history. A single instance is shared by
/// every page so switching chats, creating new chats and saving messages stay
/// consistent across navigation. UI can statelessly listen via
/// `ListenableBuilder(listenable: ChatHistoryController.instance, ...)`.
class ChatHistoryController extends ChangeNotifier {
  ChatHistoryController._();

  static final ChatHistoryController instance = ChatHistoryController._();

  /// Safe to use anywhere; null until [activeConversationId] is set.
  static bool get isAvailable => SupabaseService.ready;

  List<ConversationModel> conversations = [];
  List<ChatMessageModel> messages = [];

  String? _activeConversationId;
  String? get activeConversationId => _activeConversationId;

  bool loadingConversations = false;
  bool errorLoadingConversations = false;
  bool loadingMessages = false;
  bool errorLoadingMessages = false;

  /// Load the sidebar's recent list. Degrades to an error state instead of
  /// throwing so the page always renders.
  Future<void> refreshConversations() async {
    if (!isAvailable) {
      loadingConversations = false;
      errorLoadingConversations = true;
      notifyListeners();
      return;
    }
    loadingConversations = true;
    errorLoadingConversations = false;
    notifyListeners();

    conversations = await ChatHistoryService.fetchConversations();
    loadingConversations = false;
    errorLoadingConversations = conversations.isEmpty;
    notifyListeners();
  }

  /// Returns the id of the active conversation, creating one (owned by the
  /// current user) the first time a message is sent. Never creates a
  /// conversation just for viewing the home page.
  Future<String?> ensureActiveConversation({String? userMessage}) async {
    if (!isAvailable) return null;
    if (_activeConversationId != null) return _activeConversationId;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final title =
        (userMessage == null || userMessage.trim().isEmpty)
            ? 'New chat'
            : deriveTitle(userMessage);
    final id = await ChatHistoryService.createConversation(
      userId: userId,
      title: title,
    );
    if (id != null) {
      _activeConversationId = id;
      messages = [];
      notifyListeners();
      unawaited(refreshConversations());
    }
    return id;
  }

  Future<void> saveUserMessage(String content) async {
    final trimmed = content.trim();
    if (!isAvailable || trimmed.isEmpty) return;
    final id = await ensureActiveConversation(userMessage: trimmed);
    if (id == null) return;
    final ok = await ChatHistoryService.saveMessage(
      conversationId: id,
      role: 'user',
      content: trimmed,
    );
    if (ok) {
      unawaited(_reloadMessages(id));
      unawaited(refreshConversations());
    }
  }

  Future<void> saveAssistantMessage(
    String content, {
    Map<String, dynamic>? metadata,
  }) async {
    final trimmed = content.trim();
    // Skip empty content and the backend fallback sentinel so placeholder
    // junk never pollutes the saved history.
    const fallbackSentinel = '__FALLBACK__';
    if (!isAvailable ||
        trimmed.isEmpty ||
        trimmed == fallbackSentinel ||
        trimmed.startsWith('$fallbackSentinel ')) {
      return;
    }
    final id = _activeConversationId;
    if (id == null) return;
    final ok = await ChatHistoryService.saveMessage(
      conversationId: id,
      role: 'assistant',
      content: trimmed,
      metadata: metadata ?? const {},
    );
    if (ok) {
      unawaited(_reloadMessages(id));
      unawaited(refreshConversations());
    }
  }

  /// Open a saved conversation (renders its stored messages as history).
  Future<void> openConversation(String id) async {
    _activeConversationId = id;
    loadingMessages = true;
    errorLoadingMessages = false;
    notifyListeners();
    unawaited(refreshConversations());

    messages = await ChatHistoryService.fetchMessages(id);
    loadingMessages = false;
    errorLoadingMessages = messages.isEmpty;
    notifyListeners();
  }

  /// Start a brand-new thread. The conversation itself is created lazily on
  /// the first saved message.
  Future<void> startNewChat() async {
    _activeConversationId = null;
    messages = [];
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    if (title.trim().isEmpty) return;
    await ChatHistoryService.renameConversation(id, title.trim());
    final index = conversations.indexWhere((c) => c.id == id);
    if (index != -1) {
      conversations[index].title = title.trim();
      notifyListeners();
    }
    unawaited(refreshConversations());
  }

  Future<void> deleteConversation(String id) async {
    await ChatHistoryService.deleteConversation(id);
    conversations.removeWhere((c) => c.id == id);
    if (_activeConversationId == id) {
      _activeConversationId = null;
      messages = [];
    }
    notifyListeners();
  }

  Future<void> _reloadMessages(String id) async {
    messages = await ChatHistoryService.fetchMessages(id);
    notifyListeners();
  }

  /// Deterministic sidebar title from the first user message (no LLM).
  String deriveTitle(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return 'New chat';
    return collapsed.length <= 60
        ? collapsed
        : '${collapsed.substring(0, 60)}…';
  }
}