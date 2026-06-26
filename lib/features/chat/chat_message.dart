import '../attachments/attachment.dart';

/// A single message in a conversation.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.modelId,
    this.isStreaming = false,
    this.attachments = const [],
  });

  final String id;
  final MessageRole role;
  String content; // mutable during streaming
  final DateTime timestamp;
  final String? modelId; // which model produced this assistant message
  bool isStreaming;
  final List<ChatAttachment> attachments;

  bool get hasAttachments => attachments.isNotEmpty;

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<ChatAttachment>? attachments,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        modelId: modelId,
        isStreaming: isStreaming ?? this.isStreaming,
        attachments: attachments ?? this.attachments,
      );

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
}

enum MessageRole { user, assistant, system }

// ─────────────────────────────────────────────────────────────────────────────
// Chat session
// ─────────────────────────────────────────────────────────────────────────────

class ChatSession {
  ChatSession({
    required this.id,
    required this.createdAt,
    this.title,
    this.modelId,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  final String id;
  final DateTime createdAt;
  String? title;
  String? modelId;
  List<ChatMessage> messages;

  String get displayTitle {
    if (title != null) return title!;
    final first = messages.where((m) => m.isUser).firstOrNull;
    return first != null ? _truncate(first.content) : 'New chat';
  }

  static String _truncate(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;
}
