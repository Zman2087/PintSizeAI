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

/// Whether the AI remembers context/feedback across chats.
final memoryEnabledProvider = StateNotifierProvider<_BoolNotifier, bool>((ref) {
  final notifier = _BoolNotifier(true);
  ref.read(settingsServiceProvider).getMemoryEnabled().then(notifier._set);
  return notifier;
});

/// The selected TTS voice identifier (null = system default).
final selectedVoiceProvider =
    StateNotifierProvider<_StringNotifier, String?>((ref) {
  final notifier = _StringNotifier(null);
  ref.read(settingsServiceProvider).getVoiceId().then(notifier._set);
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

class _DoubleNotifier extends StateNotifier<double> {
  _DoubleNotifier(super.state);
  void _set(double v) => state = v;
  void set(double v) => state = v;
}

class _IntNotifier extends StateNotifier<int> {
  _IntNotifier(super.state);
  void _set(int v) => state = v;
  void set(int v) => state = v;
}

/// LLM sampling temperature (0.0 – 2.0, default 0.7).
final temperatureProvider =
    StateNotifierProvider<_DoubleNotifier, double>((ref) {
  final n = _DoubleNotifier(0.7);
  ref.read(settingsServiceProvider).getTemperature().then(n._set);
  return n;
});

/// Nucleus sampling top-p (0.0 – 1.0, default 0.9).
final topPProvider = StateNotifierProvider<_DoubleNotifier, double>((ref) {
  final n = _DoubleNotifier(0.9);
  ref.read(settingsServiceProvider).getTopP().then(n._set);
  return n;
});

/// Max tokens per response (64 – 2048, default 512).
final maxTokensProvider = StateNotifierProvider<_IntNotifier, int>((ref) {
  final n = _IntNotifier(512);
  ref.read(settingsServiceProvider).getMaxTokens().then(n._set);
  return n;
});

/// Whether TTS speaks sentence-by-sentence while AI is still generating.
final streamingTtsProvider = StateNotifierProvider<_BoolNotifier, bool>((ref) {
  final n = _BoolNotifier(false);
  ref.read(settingsServiceProvider).getStreamingTts().then(n._set);
  return n;
});

/// Whether iCloud KV sync is enabled.
final iCloudSyncProvider = StateNotifierProvider<_BoolNotifier, bool>((ref) {
  final n = _BoolNotifier(false);
  ref.read(settingsServiceProvider).getICloudSync().then(n._set);
  return n;
});
