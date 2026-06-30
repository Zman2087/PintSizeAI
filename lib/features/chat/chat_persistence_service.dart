import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'chat_message.dart';

/// Persists chat sessions to a JSON file in the app documents directory so
/// conversations survive app restarts and crashes.
///
/// Note: attachment bytes (images) are not persisted to keep the file small —
/// only the text of each message is stored.
class ChatPersistenceService {
  static const _fileName = 'chat_sessions.json';

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  Future<void> save(List<ChatSession> sessions, String? activeSessionId) async {
    try {
      final data = {
        'activeSessionId': activeSessionId,
        'sessions': sessions.map(_sessionToJson).toList(),
      };
      final file = await _file();
      // Write to a temp file then rename for crash-safe atomic replace.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(file.path);
    } catch (_) {
      // Persistence is best-effort; never crash the app over it.
    }
  }

  /// Returns the stored sessions and active id, or null if nothing saved.
  Future<({List<ChatSession> sessions, String? activeSessionId})?> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = (map['sessions'] as List?) ?? const [];
      final sessions = list
          .map((s) => _sessionFromJson(s as Map<String, dynamic>))
          .toList();
      return (
        sessions: sessions,
        activeSessionId: map['activeSessionId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _sessionToJson(ChatSession s) => {
        'id': s.id,
        'title': s.title,
        'createdAt': s.createdAt.toIso8601String(),
        'modelId': s.modelId,
        'pinned': s.pinned,
        'branchedFromSessionId': s.branchedFromSessionId,
        'branchedAtMessageIndex': s.branchedAtMessageIndex,
        'messages': s.messages
            .where((m) => m.role != MessageRole.system)
            .map((m) => {
                  'id': m.id,
                  'role': m.role.name,
                  'content': m.content,
                  'timestamp': m.timestamp.toIso8601String(),
                  'modelId': m.modelId,
                  'tokensPerSec': m.tokensPerSec,
                  'elapsedMs': m.elapsedMs,
                  'rating': m.rating,
                })
            .toList(),
      };

  ChatSession _sessionFromJson(Map<String, dynamic> j) {
    final messages = ((j['messages'] as List?) ?? const [])
        .map((m) => _messageFromJson(m as Map<String, dynamic>))
        .toList();
    return ChatSession(
      id: j['id'] as String,
      title: j['title'] as String?,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      modelId: j['modelId'] as String?,
      pinned: j['pinned'] as bool? ?? false,
      branchedFromSessionId: j['branchedFromSessionId'] as String?,
      branchedAtMessageIndex: j['branchedAtMessageIndex'] as int?,
      messages: messages,
    );
  }

  ChatMessage _messageFromJson(Map<String, dynamic> j) {
    final msg = ChatMessage(
      id: j['id'] as String,
      role: MessageRole.values
          .firstWhere((r) => r.name == j['role'], orElse: () => MessageRole.user),
      content: j['content'] as String? ?? '',
      timestamp:
          DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      modelId: j['modelId'] as String?,
    );
    msg.tokensPerSec = (j['tokensPerSec'] as num?)?.toDouble();
    msg.elapsedMs = j['elapsedMs'] as int?;
    msg.rating = j['rating'] as int?;
    return msg;
  }
}
