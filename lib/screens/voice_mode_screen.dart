import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/chat_message.dart';
import '../features/chat/chat_providers.dart';
import '../features/settings/settings_providers.dart';
import '../features/voice/voice_providers.dart';
import '../features/voice/voice_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum _Phase { idle, listening, processing, speaking }

// ── Screen ────────────────────────────────────────────────────────────────────

class VoiceModeScreen extends ConsumerStatefulWidget {
  const VoiceModeScreen({super.key});

  static void open(BuildContext ctx) => Navigator.of(ctx).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (_, __, ___) => const VoiceModeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );

  @override
  ConsumerState<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends ConsumerState<VoiceModeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  StreamSubscription<VoiceEvent>? _voiceSub;

  _Phase _phase = _Phase.idle;
  String _transcript = '';
  String _aiText = '';

  // True between sending a prompt and the assistant finishing its turn.
  bool _awaitingResponse = false;
  String? _streamingMsgId;
  bool _spoken = false;
  // True once the model has finished generating this turn's reply. Streaming
  // TTS fires "speaking_done" between sentences, so we only relisten once
  // generation is complete AND all queued speech has drained.
  bool _genDone = false;

  // Settings we temporarily override so the AI always talks back in voice mode.
  bool _savedAutoSpeak = false;
  bool _savedStreamingTts = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // While voice mode is open, force the AI to speak — and stream it
    // sentence-by-sentence so it starts talking within a second or two instead
    // of waiting for the whole reply. Restore the user's prefs on exit.
    _savedAutoSpeak = ref.read(autoSpeakProvider);
    _savedStreamingTts = ref.read(streamingTtsProvider);
    ref.read(autoSpeakProvider.notifier).set(true);
    ref.read(streamingTtsProvider.notifier).set(true);

    // Single persistent event subscription drives the whole loop.
    final voice = ref.read(voiceServiceProvider);
    _voiceSub = voice.events.listen(_onVoiceEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _voiceSub?.cancel();
    final voice = ref.read(voiceServiceProvider);
    voice.stopListening();
    voice.stopSpeaking();
    // Restore the user's TTS preferences.
    try {
      ref.read(autoSpeakProvider.notifier).set(_savedAutoSpeak);
      ref.read(streamingTtsProvider.notifier).set(_savedStreamingTts);
    } catch (_) {}
    super.dispose();
  }

  // ── Voice loop ───────────────────────────────────────────────────────────────

  void _onVoiceEvent(VoiceEvent evt) {
    if (!mounted) return;
    switch (evt) {
      case VoiceTranscriptEvent(:final text, :final isFinal):
        setState(() => _transcript = text);
        if (isFinal && text.trim().isNotEmpty && _phase == _Phase.listening) {
          _sendText(text.trim());
        }
      case VoiceListeningStoppedEvent():
        // iOS silence/timeout while we were still listening with nothing said.
        if (_phase == _Phase.listening && _transcript.trim().isEmpty) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _phase == _Phase.listening) _startListening();
          });
        }
      case VoiceSpeakingDoneEvent():
        // Streaming TTS emits this between sentences too — only move on once
        // the model has finished generating the whole reply.
        if (_phase == _Phase.speaking && _genDone) _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    final voice = ref.read(voiceServiceProvider);
    setState(() {
      _phase = _Phase.listening;
      _transcript = '';
    });
    await voice.startListening();
  }

  Future<void> _sendText(String text) async {
    final voice = ref.read(voiceServiceProvider);
    await voice.stopListening();
    await voice.stopSpeaking(); // flush any leftover speech from the last turn
    if (!mounted) return;

    setState(() {
      _phase = _Phase.processing;
      _aiText = '';
      _awaitingResponse = true;
      _streamingMsgId = null;
      _spoken = false;
      _genDone = false;
    });

    ref.read(chatControllerProvider.notifier).send(text);
  }

  // ── Watch messages for streaming progress / completion ─────────────────────────

  void _onMessagesUpdate(List<ChatMessage> messages) {
    if (!_awaitingResponse) return;

    final last = messages.lastOrNull;
    if (last == null || last.role != MessageRole.assistant) return;

    setState(() => _aiText = last.content);

    if (last.isStreaming) {
      _streamingMsgId = last.id;
      // Keep showing "Thinking…" while tokens stream in; the controller will
      // speak the full response once streaming completes.
      if (_phase != _Phase.processing) {
        setState(() => _phase = _Phase.processing);
      }
    } else if (!_spoken && last.id == _streamingMsgId) {
      // Generation finished. The controller speaks the reply (streaming TTS is
      // forced on). Move to the speaking phase; we relisten on speaking_done
      // once _genDone is set.
      _spoken = true;
      _genDone = true;
      _awaitingResponse = false;
      if (last.content.trim().isEmpty) {
        _startListening();
      } else {
        setState(() => _phase = _Phase.speaking);
        // If streaming TTS already finished speaking everything (nothing left
        // queued), there won't be another speaking_done — relisten now.
        () async {
          final speaking = await ref.read(voiceServiceProvider).isSpeaking;
          if (mounted && !speaking && _phase == _Phase.speaking) {
            _startListening();
          }
        }();
      }
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(messagesProvider, (_, messages) => _onMessagesUpdate(messages));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Spacer(),
                  const Text(
                    'Voice Mode',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _CloseButton(onTap: () {
                    Navigator.of(context).pop();
                  }),
                ],
              ),
            ),

            const Spacer(),

            // Text bubbles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_transcript.isNotEmpty && _phase == _Phase.listening)
                    _Bubble(text: _transcript, isUser: true),
                  if (_aiText.isNotEmpty) _Bubble(text: _aiText, isUser: false),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Animated orb
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => _Orb(phase: _phase, t: _pulse.value),
            ),

            const SizedBox(height: 20),

            // Phase label
            Text(
              _phaseLabel(_phase),
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),

            const SizedBox(height: 36),

            // Interrupt button
            if (_phase == _Phase.speaking || _phase == _Phase.processing)
              GestureDetector(
                onTap: () async {
                  final voice = ref.read(voiceServiceProvider);
                  await voice.stopSpeaking();
                  _awaitingResponse = false;
                  _startListening();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Interrupt',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ),
              ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  String _phaseLabel(_Phase p) => switch (p) {
        _Phase.idle => 'Starting…',
        _Phase.listening => 'Listening…',
        _Phase.processing => 'Thinking…',
        _Phase.speaking => 'Speaking…',
      };
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.close, color: Colors.white70, size: 18),
        ),
      );
}

class _Orb extends StatelessWidget {
  const _Orb({required this.phase, required this.t});
  final _Phase phase;
  final double t; // 0..1 pulse

  @override
  Widget build(BuildContext context) {
    final (color, icon, showSpinner) = switch (phase) {
      _Phase.listening => (
          const Color(0xFF22C55E),
          Icons.mic,
          false,
        ),
      _Phase.processing => (
          const Color(0xFFF59E0B),
          Icons.auto_awesome,
          true,
        ),
      _Phase.speaking => (
          const Color(0xFF3B82F6),
          Icons.volume_up_rounded,
          false,
        ),
      _Phase.idle => (Colors.white24, Icons.mic_none, false),
    };

    final scale = 1.0 + t * 0.12;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.12),
          border: Border.all(color: color.withOpacity(0.55), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.25 + t * 0.2),
              blurRadius: 28 + t * 18,
              spreadRadius: 3,
            ),
          ],
        ),
        child: showSpinner
            ? const Center(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    color: Color(0xFFF59E0B),
                    strokeWidth: 2.5,
                  ),
                ),
              )
            : Icon(icon, color: color, size: 44),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(
          bottom: 12,
          left: isUser ? 36 : 0,
          right: isUser ? 0 : 36,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF22C55E).withOpacity(0.18)
              : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUser
                ? const Color(0xFF22C55E).withOpacity(0.4)
                : Colors.white12,
          ),
        ),
        child: Text(
          text,
          style:
              const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
