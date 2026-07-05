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

  Future<void> startListening() => _method.invokeMethod<void>('startListening');

  Future<void> stopListening() => _method.invokeMethod<void>('stopListening');

  // ── TTS ──────────────────────────────────────────────────────────────────────

  Future<void> speak(String text) => _method.invokeMethod<void>('speak', text);

  Future<void> stopSpeaking() => _method.invokeMethod<void>('stopSpeaking');

  Future<bool> get isSpeaking async =>
      await _method.invokeMethod<bool>('isSpeaking') ?? false;

  Future<void> setRate(double rate) =>
      _method.invokeMethod<void>('setRate', rate);

  /// Lists the device's available TTS voices, best quality first.
  Future<List<VoiceOption>> listVoices() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('listVoices');
      if (raw == null) return [];
      return raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return VoiceOption(
          id: m['id'] as String? ?? '',
          name: m['name'] as String? ?? 'Voice',
          lang: m['lang'] as String? ?? '',
          quality: m['quality'] as String? ?? 'Standard',
          isPersonal: m['isPersonal'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Selects a voice by identifier. Pass null/empty to use the system default.
  Future<void> setVoice(String? voiceId) =>
      _method.invokeMethod<void>('setVoice', voiceId ?? '');

  /// Current Personal Voice authorization: authorized/denied/notDetermined/
  /// unsupported.
  Future<String> personalVoiceStatus() async =>
      await _method.invokeMethod<String>('personalVoiceStatus') ??
      'unsupported';

  /// Prompts the user to allow this app to use their Personal Voice.
  Future<String> requestPersonalVoice() async =>
      await _method.invokeMethod<String>('requestPersonalVoice') ??
      'unsupported';

  /// Opens the iOS Settings app (to create a Personal Voice under Accessibility).
  Future<void> openSettings() => _method.invokeMethod<void>('openSettings');

  void dispose() {
    _sub?.cancel();
    _ctrl.close();
  }
}

/// A selectable text-to-speech voice.
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this.lang,
    required this.quality,
    this.isPersonal = false,
  });
  final String id;
  final String name;
  final String lang;
  final String quality;
  final bool isPersonal;
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
