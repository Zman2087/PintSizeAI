import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/model_providers.dart';
import 'chat_controller.dart';
import 'chat_message.dart';

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>(
  (ref) => ChatController(ref),
);

/// Quick access to the active session's messages for the chat list.
final messagesProvider = Provider<List<ChatMessage>>((ref) {
  return ref.watch(chatControllerProvider).messages;
});

final hasMessagesProvider = Provider<bool>((ref) {
  return ref.watch(chatControllerProvider).hasMessages;
});

final chatErrorProvider = Provider<String?>((ref) {
  return ref.watch(chatControllerProvider).error;
});

/// Estimated fraction (0..1+) of the active model's context window currently
/// used by the conversation. Uses a ~4-chars-per-token heuristic. Returns 0
/// when no model is active.
final contextUsageProvider = Provider<double>((ref) {
  final model = ref.watch(activeModelProvider);
  if (model == null) return 0.0;
  final messages = ref.watch(messagesProvider);
  var chars = 0;
  for (final m in messages) {
    chars += m.content.length;
  }
  final estTokens = chars / 4.0;
  final ctx = model.contextLength;
  if (ctx <= 0) return 0.0;
  return estTokens / ctx;
});
