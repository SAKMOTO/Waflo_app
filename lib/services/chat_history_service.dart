import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'supabase_service.dart';

/// All Supabase reads/writes for chat history. Every method is defensive:
/// returns null/false/empty on any failure so the live chat is never blocked
/// by persistence problems.
class ChatHistoryService {
  static SupabaseClient get _client => Supabase.instance.client;

  static bool get _db => SupabaseService.ready;

  static Future<String?> createConversation({
    required String userId,
    String title = 'New chat',
  }) async {
    if (!_db) return null;
    try {
      final row = await _client
          .from('conversations')
          .insert({'user_id': userId, 'title': title})
          .select()
          .single();
      return (row['id'] ?? '') as String;
    } catch (e) {
      debugLog('createConversation failed: $e');
      return null;
    }
  }

  static Future<List<ConversationModel>> fetchConversations(
      {int limit = 50}) async {
    if (!_db) return const [];
    try {
      final rows = await _client
          .from('conversations')
          .select()
          .order('updated_at', ascending: false)
          .limit(limit);
      return rows
          .map((r) => ConversationModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugLog('fetchConversations failed: $e');
      return const [];
    }
  }

  static Future<List<ChatMessageModel>> fetchMessages(
      String conversationId) async {
    if (!_db) return const [];
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return rows
          .map((r) => ChatMessageModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugLog('fetchMessages failed: $e');
      return const [];
    }
  }

  static Future<bool> saveMessage({
    required String conversationId,
    required String role,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (!_db) return false;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'user_id': userId,
        'role': role,
        'content': content,
        'metadata': metadata,
      });
      await _client
          .from('conversations')
          .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', conversationId);
      return true;
    } catch (e) {
      debugLog('saveMessage failed: $e');
      return false;
    }
  }

  static Future<bool> renameConversation(String id, String title) async {
    if (!_db) return false;
    try {
      await _client.from('conversations').update({'title': title}).eq('id', id);
      return true;
    } catch (e) {
      debugLog('renameConversation failed: $e');
      return false;
    }
  }

  static Future<bool> deleteConversation(String id) async {
    if (!_db) return false;
    try {
      await _client
          .from('messages')
          .delete()
          .eq('conversation_id', id);
      await _client.from('conversations').delete().eq('id', id);
      return true;
    } catch (e) {
      debugLog('deleteConversation failed: $e');
      return false;
    }
  }

  static void debugLog(String message) {
    // TODO: route through the app logger if one is added.
    // ignore: avoid_print
    print('[ChatHistory] $message');
  }
}