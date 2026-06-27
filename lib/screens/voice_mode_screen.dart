import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/chat_message.dart';
import '../features/chat/chat_providers.dart';
import '../features/voice/voice_providers.dart';
import '../features/voice/voice_service.dart';
import '../theme/theme.dart';

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
  bool _waitingForStream = false;
  String? _lastStreamingMsgId;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _voiceSub?.cancel();
    super.dispose();
  }

  // ── Voice loop ───────────────────────────────────────────────────────────────

  void _setPhase(_Phase p) {
    if (mounted) setState(() => _phase = p);
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    final voice = ref.read(voiceServiceProvider);
    setState(() {
      _phase = _Phase.listening;
      _transcript = '';
      _aiText = '';
      _waitingForStream = false;
      _lastStreamingMsgId = null;
    });

    await voice.startListening();

    _voiceSub?.cancel();
    _voiceSub = voice.events.listen((evt) {
      if (!mounted) return;
      switch (evt) {
        case VoiceTranscriptEvent(:final text, :final isFinal):
          setState(() => _transcript = text);
          if (isFinal && text.trim().isNotEmpty) {
            _sendText(text.trim());
          }
        case VoiceListeningStoppedEvent():
          if (_phase == _Phase.listening) {
            // iOS silence timeout — restart
            Future.delayed(
              const Duration(milliseconds: 500),
              _startListening,
            );
          }
        case VoiceSpeakingDoneEvent():
          _startListening();
      }
    });
  }

  Future<void> _sendText(String text) async {
    _voiceSub?.cancel();
    final voice = ref.read(voiceServiceProvider);
    await voice.stopListening();

    if (!mounted) return;
    setState(() {
      _phase = _Phase.processing;
      _aiText = '';
      _waitingForStream = true;
    });

    ref.read(chatControllerProvider.notifier).send(text);
  }

  Future<void> _speakAiText(String text) async {
    if (!mounted || text.isEmpty) {
      _startListening();
      return;
    }
    setState(() => _phase = _Phase.speaking);
    _voiceSub?.cancel();
    final voice = ref.read(voiceServiceProvider);
    await voice.speak(text);

    _voiceSub = voice.events.listen((evt) {
      if (!mounted) return;
      if (evt is VoiceSpeakingDoneEvent) {
        _voiceSub?.cancel();
        _startListening();
      }
    });
  }

  // ── Watch messages for streaming completion ───────────────────────────────────

  void _onMessagesUpdate(List<ChatMessage> messages) {
    if (!_waitingForStream) return;

    // Find the last assistant message
    final last = messages.lastOrNull;
    if (last == null || last.role != MessageRole.assistant) return;

    if (mounted) setState(() => _aiText = last.content);

    if (last.isStreaming) {
      // Still coming in — show processing→speaking transition
      if (_phase == _Phase.processing && last.content.isNotEmpty) {
        setState(() => _phase = _Phase.speaking);
      }
      _lastStreamingMsgId = last.id;
    } else if (_lastStreamingMsgId != null &&
        last.id == _lastStreamingMsgId &&
        !last.isStreaming) {
      // Stream just finished
      _waitingForStream = false;
      _lastStreamingMsgId = null;
      _speakAiText(last.content);
    } else if (_waitingForStream && !last.isStreaming && last.content.isNotEmpty) {
      // Catch first arrival if we missed the streaming message
      _waitingForStream = false;
      _speakAiText(last.content);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch messages to detect streaming completion
    ref.listen(messagesProvider, (_, messages) => _onMessagesUpdate(messages));

    return Scaffold(
      backgroundColor: const Color(0xF00A0F1A),
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
                  _CloseButton(onTap: () async {
                    _voiceSub?.cancel();
                    final voice = ref.read(voiceServiceProvider);
                    await voice.stopListening();
                    await voice.stopSpeaking();
                    if (mounted) Navigator.of(context).pop();
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
                  if (_aiText.isNotEmpty)
                    _Bubble(text: _aiText, isUser: false),
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
                  _startListening();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
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
        _Phase.idle => 'Starting...',
        _Phase.listening => 'Listening...',
        _Phase.processing => 'Thinking...',
        _Phase.speaking => 'Speaking...',
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
          style: const TextStyle(
              color: Colors.white, fontSize: 15, height: 1.4),
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
