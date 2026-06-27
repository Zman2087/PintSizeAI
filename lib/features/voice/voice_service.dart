import 'dart:async';
import 'package:flutter/services.dart';

/// Bridges to VoicePlugin.swift for STT + TTS.
class VoiceService {
  static const _method = MethodChannel('pintsize/voice');
  static const _events = EventChannel('pintsize/voice_text');

  StreamSubscription<dynamic>? _sub;

  // ── Speech-to-text ──────────────────────────────────────────────────────────

  /// Starts listening and streams transcript updates.
  /// Each event is a [VoiceTranscript] with text + isFinal flag.
  Stream<VoiceTranscript> startListening() {
    final ctrl = StreamController<VoiceTranscript>.broadcast();

    _method.invokeMethod<void>('startListening').catchError((e) {
      ctrl.addError(e);
      ctrl.close();
    });

    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          ctrl.add(VoiceTranscript(
            text: event['text'] as String? ?? '',
            isFinal: event['isFinal'] as bool? ?? false,
          ));
        }
      },
      onError: ctrl.addError,
      onDone: ctrl.close,
    );

    ctrl.onCancel = () {
      _sub?.cancel();
      _method.invokeMethod<void>('stopListening');
    };

    return ctrl.stream;
  }

  Future<void> stopListening() async {
    await _sub?.cancel();
    _sub = null;
    await _method.invokeMethod<void>('stopListening');
  }

  // ── Text-to-speech ──────────────────────────────────────────────────────────

  Future<void> speak(String text) =>
      _method.invokeMethod<void>('speak', text);

  Future<void> stopSpeaking() =>
      _method.invokeMethod<void>('stopSpeaking');

  Future<bool> get isSpeaking async =>
      await _method.invokeMethod<bool>('isSpeaking') ?? false;

  /// rate: 0.0 (slow) → 1.0 (fast). Default ≈ 0.5.
  Future<void> setRate(double rate) =>
      _method.invokeMethod<void>('setRate', rate);
}

class VoiceTranscript {
  const VoiceTranscript({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}
