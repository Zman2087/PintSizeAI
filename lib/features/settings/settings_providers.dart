import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (_) => SettingsService(),
);

/// Triggers auto-load of the last used model on app startup.
final autoLoadLastModelProvider = FutureProvider<String?>((ref) async {
  return ref.read(settingsServiceProvider).getLastModelId();
});

/// Custom system prompt set by the user. Null = use the built-in default.
final customSystemPromptProvider =
    StateNotifierProvider<_StringNotifier, String?>((ref) {
  final notifier = _StringNotifier(null);
  ref.read(settingsServiceProvider).getSystemPrompt().then(notifier._set);
  return notifier;
});

/// Persistent memory snippets loaded from disk.
final persistentMemoriesProvider =
    StateNotifierProvider<_ListNotifier, List<String>>((ref) {
  final notifier = _ListNotifier([]);
  ref.read(settingsServiceProvider).getMemories().then(notifier._set);
  return notifier;
});

/// Whether AI responses are automatically spoken aloud.
final autoSpeakProvider = StateNotifierProvider<_BoolNotifier, bool>((ref) {
  final notifier = _BoolNotifier(false);
  ref.read(settingsServiceProvider).getAutoSpeak().then(notifier._set);
  return notifier;
});

// ─── Thin notifier helpers ────────────────────────────────────────────────────

class _StringNotifier extends StateNotifier<String?> {
  _StringNotifier(super.state);
  void _set(String? v) => state = v;
  void update(String? v) => state = v;
}

class _ListNotifier extends StateNotifier<List<String>> {
  _ListNotifier(super.state);
  void _set(List<String> v) => state = v;
  void add(String s) => state = [s, ...state].take(12).toList();
  void clear() => state = [];
}

class _BoolNotifier extends StateNotifier<bool> {
  _BoolNotifier(super.state);
  void _set(bool v) => state = v;
  void toggle() => state = !state;
  void set(bool v) => state = v;
}
