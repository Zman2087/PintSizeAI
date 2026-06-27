import 'dart:async';
import 'package:flutter/services.dart';

class VoiceService {
  static const _method = MethodChannel('pintsize/voice');
  static const _events = EventChannel('pintsize/voice_text');

  StreamSubscription<dynamic>? _sub;
  final _ctrl = StreamController<VoiceEvent>.broadcast();

  /// Unified event stream: transcripts, speaking_done, listening_stopped.
  Stream<VoiceEvent> get events => _ctrl.stream;

  VoiceService() {
    _sub = _events.receiveBroadcastStream().listen(
      (raw) {
        if (raw is Map) {
          final type = raw['type'] as String? ?? '';
          switch (type) {
            case 'transcript':
              _ctrl.add(VoiceTranscriptEvent(
                text: raw['text'] as String? ?? '',
                isFinal: raw['isFinal'] as bool? ?? false,
              ));
            case 'speaking_done':
              _ctrl.add(const VoiceSpeakingDoneEvent());
            case 'listening_stopped':
              _ctrl.add(const VoiceListeningStoppedEvent());
          }
        }
      },
      onError: _ctrl.addError,
    );
  }

  // ── STT ──────────────────────────────────────────────────────────────────────

  Future<void> startListening() =>
      _method.invokeMethod<void>('startListening');

  Future<void> stopListening() =>
      _method.invokeMethod<void>('stopListening');

  // ── TTS ──────────────────────────────────────────────────────────────────────

  Future<void> speak(String text) =>
      _method.invokeMethod<void>('speak', text);

  Future<void> stopSpeaking() =>
      _method.invokeMethod<void>('stopSpeaking');

  Future<bool> get isSpeaking async =>
      await _method.invokeMethod<bool>('isSpeaking') ?? false;

  Future<void> setRate(double rate) =>
      _method.invokeMethod<void>('setRate', rate);

  void dispose() {
    _sub?.cancel();
    _ctrl.close();
  }
}

// ── Event types ───────────────────────────────────────────────────────────────

sealed class VoiceEvent {
  const VoiceEvent();
}

class VoiceTranscriptEvent extends VoiceEvent {
  const VoiceTranscriptEvent({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}

class VoiceSpeakingDoneEvent extends VoiceEvent {
  const VoiceSpeakingDoneEvent();
}

class VoiceListeningStoppedEvent extends VoiceEvent {
  const VoiceListeningStoppedEvent();
}
