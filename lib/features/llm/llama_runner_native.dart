import 'dart:async';
import 'package:flutter/services.dart';
import '../device_recommender/model_catalogue.dart';
import 'llama_runner.dart';

/// Real on-device inference via llama.cpp (iOS).
///
/// Communicates with [LlamaPlugin] in Swift:
///   MethodChannel pintsize/llama        — load / unload / cancel
///   EventChannel  pintsize/llama_stream — streams one token String per event
class LlamaRunnerNative implements LlamaRunner {
  static const _method = MethodChannel('pintsize/llama');
  static const _events = EventChannel('pintsize/llama_stream');

  LlamaStatus _status = LlamaStatus.idle;
  ModelVariant? _loadedModel;
  String? _lastError;

  @override
  LlamaStatus get status => _status;

  @override
  ModelVariant? get loadedModel => _loadedModel;

  @override
  String? get lastError => _lastError;

  // ── Load / unload ──────────────────────────────────────────────────────────

  @override
  Future<void> load(ModelVariant model, String modelPath) async {
    _status = LlamaStatus.loading;
    _lastError = null;

    try {
      await _method.invokeMethod<void>('loadModel', {
        'path': modelPath,
        // Keep context ≤ 4096 for RAM safety; real limit is capped in Swift too
        'contextLength': model.contextLength.clamp(512, 4096),
      });
      _loadedModel = model;
      _status = LlamaStatus.ready;
    } on PlatformException catch (e) {
      _lastError = e.message;
      _status = LlamaStatus.error;
      rethrow;
    }
  }

  @override
  Future<void> unload() async {
    await _method.invokeMethod<void>('unloadModel');
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
  }) async* {
    _status = LlamaStatus.generating;

    try {
      final stream = _events.receiveBroadcastStream({
        'prompt': prompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
      });

      await for (final token in stream.cast<String>()) {
        yield token;
      }
    } on PlatformException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      if (_status == LlamaStatus.generating) {
        _status = LlamaStatus.ready;
      }
    }
  }

  // ── Cancel ─────────────────────────────────────────────────────────────────

  @override
  void cancelGeneration() {
    _method.invokeMethod<void>('cancelGeneration');
    _status = LlamaStatus.ready;
  }

  @override
  void dispose() {
    _method.invokeMethod<void>('unloadModel');
    _loadedModel = null;
    _status = LlamaStatus.idle;
  }
}
