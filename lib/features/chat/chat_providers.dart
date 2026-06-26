import 'package:flutter_riverpod/flutter_riverpod.dart';
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
