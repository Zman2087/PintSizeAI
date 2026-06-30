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
    this.tokensPerSec,
    this.elapsedMs,
  });

  final String id;
  final MessageRole role;
  String content; // mutable during streaming
  final DateTime timestamp;
  final String? modelId; // which model produced this assistant message
  bool isStreaming;
  final List<ChatAttachment> attachments;

  /// Generation speed for assistant messages (tokens per second).
  double? tokensPerSec;

  /// Wall-clock generation time in milliseconds for assistant messages.
  int? elapsedMs;

  /// User feedback on an assistant message: 1 = liked, -1 = disliked, null = none.
  int? rating;

  bool get hasAttachments => attachments.isNotEmpty;

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<ChatAttachment>? attachments,
    double? tokensPerSec,
    int? elapsedMs,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        modelId: modelId,
        isStreaming: isStreaming ?? this.isStreaming,
        attachments: attachments ?? this.attachments,
        tokensPerSec: tokensPerSec ?? this.tokensPerSec,
        elapsedMs: elapsedMs ?? this.elapsedMs,
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
    this.branchedFromSessionId,
    this.branchedAtMessageIndex,
    this.pinned = false,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  final String id;
  final DateTime createdAt;
  String? title;
  String? modelId;
  bool pinned;
  List<ChatMessage> messages;

  /// If this session was forked from another, records the parent session id.
  final String? branchedFromSessionId;

  /// The message index in the parent session where this branch starts.
  final int? branchedAtMessageIndex;

  String get displayTitle {
    if (title != null) return title!;
    final first = messages.where((m) => m.isUser).firstOrNull;
    return first != null ? _truncate(first.content) : 'New chat';
  }

  static String _truncate(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;
}
