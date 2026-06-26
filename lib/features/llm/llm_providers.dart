import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'llama_runner.dart';
import 'llama_runner_mock.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Singleton runner
// ─────────────────────────────────────────────────────────────────────────────

/// The active LlamaRunner instance.
///
/// Swap [LlamaRunnerMock] for LlamaRunnerFfi here once the native
/// xcframework/SO is compiled and linked into the app target.
final llamaRunnerProvider = Provider<LlamaRunner>((ref) {
  final runner = LlamaRunnerMock();
  ref.onDispose(runner.dispose);
  return runner;
});

// ─────────────────────────────────────────────────────────────────────────────
// Status providers
// ─────────────────────────────────────────────────────────────────────────────

/// Source-of-truth for the runner's current lifecycle state.
/// Updated by [ModelActions] after every load/unload and by [ChatController]
/// during generation.
final llamaStatusProvider =
    StateProvider<LlamaStatus>((ref) => LlamaStatus.idle);

/// True when the runner is streaming tokens.
final isGeneratingProvider = Provider<bool>((ref) {
  return ref.watch(llamaStatusProvider) == LlamaStatus.generating;
});

/// True when a model is loaded and can accept new prompts.
final modelReadyProvider = Provider<bool>((ref) {
  return ref.watch(llamaStatusProvider) == LlamaStatus.ready;
});
