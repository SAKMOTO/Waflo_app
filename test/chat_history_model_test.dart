import 'package:flutter_test/flutter_test.dart';

import 'package:waflo_app/models/chat_message_model.dart';
import 'package:waflo_app/models/conversation_model.dart';

void main() {
  group('ConversationModel', () {
    test('parses a Supabase row', () {
      final model = ConversationModel.fromJson({
        'id': 'c1',
        'title': 'My first chat',
        'created_at': '2026-01-02T03:04:05.000+00:00',
        'updated_at': '2026-01-02T04:05:06.000+00:00',
      });

      expect(model.id, 'c1');
      expect(model.title, 'My first chat');
      expect(model.createdAt.isUtc, isTrue);
    });

    test('falls back to safe values for malformed rows', () {
      final model = ConversationModel.fromJson(const {});
      expect(model.id, '');
      expect(model.title, 'New chat');
    });
  });

  group('ChatMessageModel', () {
    test('parses a Supabase row with metadata', () {
      final model = ChatMessageModel.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'role': 'assistant',
        'content': 'Hello',
        'metadata': {'sources': ['https://example.com']},
        'created_at': '2026-01-02T03:04:05.000+00:00',
      });

      expect(model.id, 'm1');
      expect(model.conversationId, 'c1');
      expect(model.role, 'assistant');
      expect(model.content, 'Hello');
      expect(model.metadata['sources'], ['https://example.com']);
    });

    test('defaults metadata to an empty map', () {
      final model = ChatMessageModel.fromJson({
        'id': 'm2',
        'conversation_id': 'c1',
        'role': 'user',
        'content': 'Hi',
      });
      expect(model.metadata, isEmpty);
    });
  });
}