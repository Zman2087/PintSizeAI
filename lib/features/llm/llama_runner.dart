import '../../features/device_recommender/model_catalogue.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Status
// ─────────────────────────────────────────────────────────────────────────────

enum LlamaStatus { idle, loading, ready, generating, error }

// ─────────────────────────────────────────────────────────────────────────────
// Abstract interface
// ─────────────────────────────────────────────────────────────────────────────

/// Contract for the on-device inference engine.
///
/// Two implementations exist:
///   [LlamaRunnerMock]  — streams realistic fake tokens; no native library needed.
///   LlamaRunnerFfi     — real llama.cpp via FFI; requires compiled xcframework/so.
///
/// Swap the active implementation in [llmProviders].
abstract class LlamaRunner {
  LlamaStatus get status;
  ModelVariant? get loadedModel;
  String? get lastError;

  /// Load a GGUF model file from [modelPath].
  /// Emits [LlamaStatus.loading] → [LlamaStatus.ready] or [LlamaStatus.error].
  Future<void> load(ModelVariant model, String modelPath);

  /// Unload the current model and free native memory.
  Future<void> unload();

  /// Stream tokens for [prompt] until done or [cancelGeneration] is called.
  /// Each event is a raw token string (may be a sub-word).
  Stream<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
  });

  /// Signal the runner to stop at the next token boundary.
  void cancelGeneration();

  void dispose();
}
