import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'llama_runner.dart';
import 'llama_runner_mock.dart';
import 'llama_runner_native.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active runner
// ─────────────────────────────────────────────────────────────────────────────

/// Returns [LlamaRunnerNative] on iOS (real llama.cpp inference) and
/// [LlamaRunnerMock] on every other platform (Android, macOS, web).
final llamaRunnerProvider = Provider<LlamaRunner>((ref) {
  final runner = Platform.isIOS ? LlamaRunnerNative() : LlamaRunnerMock();
  ref.onDispose(runner.dispose);
  return runner;
});

// ─────────────────────────────────────────────────────────────────────────────
// Status providers
// ─────────────────────────────────────────────────────────────────────────────

final llamaStatusProvider =
    StateProvider<LlamaStatus>((ref) => LlamaStatus.idle);

final isGeneratingProvider = Provider<bool>((ref) {
  return ref.watch(llamaStatusProvider) == LlamaStatus.generating;
});

final modelReadyProvider = Provider<bool>((ref) {
  return ref.watch(llamaStatusProvider) == LlamaStatus.ready;
});
