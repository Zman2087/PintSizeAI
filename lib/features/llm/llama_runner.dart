import 'dart:typed_data';
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

  /// Whether a multimodal projector is loaded so the model can see images.
  bool get hasVision;

  /// Load a GGUF model file from [modelPath].
  /// Emits [LlamaStatus.loading] → [LlamaStatus.ready] or [LlamaStatus.error].
  Future<void> load(ModelVariant model, String modelPath);

  /// Load a multimodal projector (mmproj GGUF) so the model can accept images.
  /// Returns true on success. Call after [load].
  Future<bool> loadProjector(String mmprojPath);

  /// Formats [messages] (each {'role':..,'content':..}) using the loaded
  /// model's own chat template. Returns null if unavailable (caller falls back).
  Future<String?> applyChatTemplate(List<Map<String, String>> messages);

  /// Unload the current model and free native memory.
  Future<void> unload();

  /// Stream tokens for [prompt] until done or [cancelGeneration] is called.
  /// Each event is a raw token string (may be a sub-word). If [imageBytes] is
  /// provided and a projector is loaded, the model sees the image.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    Uint8List? imageBytes,
  });

  /// Signal the runner to stop at the next token boundary.
  void cancelGeneration();

  void dispose();
}
