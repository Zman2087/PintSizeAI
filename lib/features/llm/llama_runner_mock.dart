import 'dart:async';
import 'dart:typed_data';
import '../../features/device_recommender/model_catalogue.dart';
import 'llama_runner.dart';

/// Development mock that streams plausible fake tokens without a native library.
///
/// Token delivery is paced to mimic the speed of a real mid-range device (~10 t/s).
/// Answers are canned but structurally realistic (full sentences, varied lengths).
/// Swap in LlamaRunnerFfi once the xcframework/SO is compiled.
class LlamaRunnerMock implements LlamaRunner {
  @override
  LlamaStatus get status => _status;
  LlamaStatus _status = LlamaStatus.idle;

  @override
  ModelVariant? get loadedModel => _loadedModel;
  ModelVariant? _loadedModel;

  @override
  String? get lastError => _lastError;
  String? _lastError;

  @override
  bool get hasVision => _hasVision;
  bool _hasVision = false;

  bool _cancelled = false;

  // ── Load / unload ──────────────────────────────────────────────────────────

  @override
  Future<void> load(ModelVariant model, String modelPath) async {
    if (_status == LlamaStatus.generating) {
      cancelGeneration();
      await Future.delayed(const Duration(milliseconds: 150));
    }
    _status = LlamaStatus.loading;
    _lastError = null;

    // Simulate the 2-3s warmup of a real GGUF load (memory mapping + layer init)
    await Future.delayed(const Duration(milliseconds: 1800));

    _loadedModel = model;
    _hasVision = false;
    _status = LlamaStatus.ready;
  }

  @override
  Future<bool> loadProjector(String mmprojPath) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _hasVision = true;
    return true;
  }

  @override
  Future<String?> applyChatTemplate(List<Map<String, String>> messages) async =>
      null; // mock has no native template; controller falls back to ChatML

  @override
  Future<void> unload() async {
    if (_status == LlamaStatus.generating) cancelGeneration();
    await Future.delayed(const Duration(milliseconds: 200));
    _loadedModel = null;
    _status = LlamaStatus.idle;
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    Uint8List? imageBytes,
  }) async* {
    if (_status != LlamaStatus.ready) {
      yield* Stream.error(
        StateError('Cannot generate: model not loaded (status: $_status)'),
      );
      return;
    }

    _cancelled = false;
    _status = LlamaStatus.generating;

    try {
      final answer = _buildAnswer(prompt);
      final tokens = _tokenise(answer);

      for (final token in tokens) {
        if (_cancelled) break;
        yield token;
        // ~10 tokens/sec → 100ms per token
        await Future.delayed(const Duration(milliseconds: 95));
      }
    } finally {
      if (!_cancelled) _status = LlamaStatus.ready;
    }
  }

  @override
  void cancelGeneration() {
    _cancelled = true;
    _status = LlamaStatus.ready;
  }

  @override
  void dispose() {
    _cancelled = true;
    _loadedModel = null;
    _status = LlamaStatus.idle;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Splits answer text into sub-word tokens that approximate real LLM output.
  /// Real llama.cpp produces BPE tokens; we split on spaces but keep punctuation
  /// attached so the streaming text feels natural.
  List<String> _tokenise(String text) {
    final tokens = <String>[];
    for (final word in text.split(' ')) {
      if (tokens.isEmpty) {
        tokens.add(word);
      } else {
        tokens.add(' $word');
      }
    }
    return tokens;
  }

  /// Returns a canned answer that varies based on question keywords.
  /// Structured to feel like a real LLM response — complete sentences,
  /// 2-4 paragraphs, no markdown (this is tuned for spoken Siri output too).
  String _buildAnswer(String prompt) {
    final q = prompt.toLowerCase();

    if (_containsAny(q, ['hello', 'hi ', 'hey', 'greet'])) {
      return 'Hello! I\'m PintSizeAi, your private on-device assistant. '
          'Everything I generate stays on your device — no cloud, no data sent anywhere. '
          'What can I help you with today?';
    }

    if (_containsAny(q, ['capital', 'country', 'city'])) {
      return 'The capital of France is Paris. '
          'It has served as the country\'s capital since the late 10th century and is home to about 2.1 million people in the city proper. '
          'Landmarks include the Eiffel Tower, the Louvre, and Notre-Dame Cathedral.';
    }

    if (_containsAny(q, ['weather', 'temperature', 'rain', 'sunny'])) {
      return 'I don\'t have access to live weather data since I run entirely offline on your device. '
          'For current conditions, please check a weather app or website. '
          'What I can help with is anything that doesn\'t require a live internet connection.';
    }

    if (_containsAny(q, ['code', 'function', 'dart', 'swift', 'python', 'javascript', 'kotlin'])) {
      return 'Happy to help with code. '
          'Could you share the specific function or problem you\'re working on? '
          'I can write, review, debug, or explain code in Dart, Swift, Kotlin, Python, JavaScript, and most other common languages.';
    }

    if (_containsAny(q, ['time', 'date', 'today', 'now'])) {
      final now = DateTime.now();
      final months = ['January','February','March','April','May','June',
                      'July','August','September','October','November','December'];
      return 'Today is ${months[now.month - 1]} ${now.day}, ${now.year}. '
          'The current time is ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}. '
          'I get this from your device\'s system clock, not the internet.';
    }

    if (_containsAny(q, ['explain', 'what is', 'how does', 'define'])) {
      return 'That\'s a great question. '
          'To give you the most accurate explanation, could you be a bit more specific about which aspect you\'d like me to focus on? '
          'I can go deep on the technical details or keep it high-level — just let me know what\'s most useful.';
    }

    if (_containsAny(q, ['make an image', 'generate an image', 'create an image',
        'draw ', 'paint ', 'make a picture', 'generate a picture',
        'make a photo', '/imagine'])) {
      return 'Generating image — tap the + button and choose "Generate Image", '
          'or just type "make an image of …" and I\'ll route it directly to the '
          'on-device image generator automatically.';
    }

    if (_containsAny(q, ['make a video', 'generate a video', 'create a video',
        'animate '])) {
      return 'Generating video — tap the + button and choose "Generate Video", '
          'or type "make a video of …" and I\'ll route it to the on-device '
          'video generator automatically.';
    }

    if (_containsAny(q, ['siri', 'voice', 'speak'])) {
      return 'Siri integration is working correctly. '
          'I can hear your questions through Siri and respond without opening the app. '
          'Everything is processed locally on your device — your voice queries never leave your phone.';
    }

    if (_containsAny(q, ['model', 'llm', 'ai', 'llama', 'neural'])) {
      final model = _loadedModel;
      if (model != null) {
        return 'You\'re currently running ${model.displayName} — a ${model.parametersBillions}B parameter model '
            'at ${model.quant.label} quantisation. '
            'It supports a ${model.contextLength ~/ 1024}k token context window. '
            'All inference happens on this device using your chip\'s compute units.';
      }
      return 'I\'m running as a local language model on your device. '
          'No data is transmitted to any server. '
          'The model file lives in your app\'s document storage and runs directly on the device\'s chip.';
    }

    // Default: thoughtful generic response
    return 'That\'s an interesting question. '
        'As an on-device assistant, I have broad knowledge from my training data '
        'but no access to real-time information or the internet. '
        'I can reason, write, explain, summarise, and help with a wide range of tasks. '
        'Could you give me a bit more context so I can give you the most useful answer?';
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
