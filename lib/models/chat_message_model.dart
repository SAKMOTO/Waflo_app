class ChatMessageModel {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ChatMessageModel({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.metadata = const {},
    required this.createdAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    return ChatMessageModel(
      id: (json['id'] ?? '') as String,
      conversationId: (json['conversation_id'] ?? '') as String,
      role: (json['role'] ?? 'user') as String,
      content: (json['content'] ?? '') as String,
      metadata: rawMetadata is Map<String, dynamic>
          ? rawMetadata
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}