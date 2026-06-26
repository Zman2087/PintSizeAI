import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_providers.dart';

final siriServiceProvider = Provider<SiriService>((ref) {
  return SiriService(ref: ref);
});

class SiriService {
  SiriService({required this.ref});

  final Ref ref;

  static const _channel = MethodChannel('com.mypocketai/siri');

  bool _initialised = false;

  void init() {
    if (!Platform.isIOS) return;
    if (_initialised) return;
    _initialised = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  // ── Incoming from native ───────────────────────────────────────────────────

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'siriQuestion':
        final question = call.arguments as String?;
        if (question == null || question.isEmpty) return null;
        await _processQuestion(question);

      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented on Flutter side.',
        );
    }
  }

  // ── Core: full inference via ChatController ────────────────────────────────

  Future<void> _processQuestion(String question) async {
    try {
      final controller = ref.read(chatControllerProvider.notifier);
      final answer = await controller.generateForSiri(question);
      await _sendAnswer(answer.isEmpty ? 'I could not generate a response.' : answer);
    } catch (e) {
      await _sendAnswer('Sorry, something went wrong. Please try again.');
    }
  }

  // ── Outgoing to native ─────────────────────────────────────────────────────

  Future<void> _sendAnswer(String answer) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('answerReady', answer);
    } on PlatformException {
      // Intent will time out — non-fatal.
    }
  }

  /// Called by model loading code to tell the Siri intent whether IPC is viable.
  Future<void> setModelReady(bool ready) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('modelLoaded', ready);
    } on PlatformException {
      // Non-critical path.
    }
  }

  // ── Prompt helpers (used by _processQuestion via ChatController) ───────────

  String buildSiriPrompt(String question) =>
      'You are PintSizeAi, a private on-device assistant. '
      'Answer the following question in 2-3 plain sentences. '
      'Do not use bullet points, markdown, or code formatting — '
      'this answer will be spoken aloud. Be direct and concise.\n\n'
      'Question: $question\n\nAnswer:';
}
