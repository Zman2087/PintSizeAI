import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../attachments/attachment.dart';
import '../device_recommender/model_catalogue.dart';
import '../llm/llama_runner.dart';
import '../llm/llm_providers.dart';
import '../settings/settings_providers.dart';
import '../settings/settings_service.dart';
import '../sync/cloud_sync_service.dart';
import '../voice/voice_providers.dart';
import 'chat_message.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class ChatState {
  const ChatState({
    required this.sessions,
    required this.activeSessionId,
    this.error,
  });

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final String? error;

  ChatSession? get activeSession =>
      sessions.where((s) => s.id == activeSessionId).firstOrNull;

  List<ChatMessage> get messages => activeSession?.messages ?? [];

  bool get hasMessages => messages.isNotEmpty;

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeSessionId,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        sessions: sessions ?? this.sessions,
        activeSessionId: activeSessionId ?? this.activeSessionId,
        error: clearError ? null : error ?? this.error,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._ref)
      : super(const ChatState(sessions: [], activeSessionId: null));

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;
  final _cloudSync = CloudSyncService();

  // Debounced cloud save — wait 3s after last change to avoid thrashing
  Timer? _syncTimer;
  void _scheduleCloudSave() {
    if (!(_ref.read(iCloudSyncProvider))) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 3), _saveToCloud);
  }

  Future<void> _saveToCloud() async {
    try {
      final sessions = state.sessions.map((s) => {
        'id': s.id,
        'title': s.title,
        'createdAt': s.createdAt.toIso8601String(),
        'messages': s.messages.map((m) => {
          'id': m.id,
          'role': m.role.name,
          'content': m.content,
          'timestamp': m.timestamp.toIso8601String(),
        }).toList(),
      }).toList();
      await _cloudSync.save(jsonEncode(sessions));
    } catch (_) {}
  }

  Future<void> loadFromCloud() async {
    try {
      final json = await _cloudSync.load();
      if (json == null) return;
      final list = jsonDecode(json) as List;
      final sessions = list.map((s) {
        final msgs = (s['messages'] as List?)?.map((m) => ChatMessage(
          id: m['id'] as String,
          role: MessageRole.values.firstWhere(
              (r) => r.name == m['role'], orElse: () => MessageRole.user),
          content: m['content'] as String,
          timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ?? DateTime.now(),
        )).toList() ?? <ChatMessage>[];
        return ChatSession(
          id: s['id'] as String,
          title: s['title'] as String?,
          createdAt: DateTime.tryParse(s['createdAt'] as String? ?? '') ?? DateTime.now(),
          messages: msgs,
        );
      }).toList();
      // Merge: keep local sessions not in cloud, add cloud sessions
      final localIds = state.sessions.map((s) => s.id).toSet();
      final newSessions = [
        ...state.sessions,
        ...sessions.where((s) => !localIds.contains(s.id)),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(sessions: newSessions);
    } catch (_) {}
  }

  // ── Session management ─────────────────────────────────────────────────────

  void newChat() {
    final session = ChatSession(
      id: _uid(),
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      activeSessionId: session.id,
      clearError: true,
    );
    _scheduleCloudSave();
  }

  void selectSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId, clearError: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void deleteSession(String sessionId) {
    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    final newActiveId = sessionId == state.activeSessionId
        ? sessions.firstOrNull?.id
        : state.activeSessionId;
    state = state.copyWith(sessions: sessions, activeSessionId: newActiveId);
    _scheduleCloudSave();
  }

  // ── Message sending ────────────────────────────────────────────────────────

  /// Adds a user message directly without requiring the LLM to be loaded.
  /// Used for image/video generation flows where inference isn't needed.
  void addUserMessage(String text, {List<ChatAttachment> attachments = const []}) {
    if (state.activeSession == null) newChat();
    final msg = ChatMessage(
      id: _uid(),
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
      attachments: attachments,
    );
    _appendMessage(msg);
    _maybeSetSessionTitle();
  }

  Future<void> send(
    String text, {
    ModelVariant? model,
    List<ChatAttachment> attachments = const [],
    String? displayText, // shown in the bubble; defaults to text
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

    // Auto-create a session if none is active
    if (state.activeSession == null) newChat();

    final runner = _ref.read(llamaRunnerProvider);
    if (runner.status != LlamaStatus.ready) {
      state = state.copyWith(
        error: 'No model loaded. Open the model picker to choose one.',
      );
      return;
    }

    // 1. Add user message (show displayText to the user, send full text to LLM)
    final userMsg = ChatMessage(
      id: _uid(),
      role: MessageRole.user,
      content: (displayText ?? text).trim(),
      timestamp: DateTime.now(),
      attachments: attachments,
    );
    _appendMessage(userMsg);

    // 2. Add placeholder assistant message (streams into it)
    final assistantMsg = ChatMessage(
      id: _uid(),
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      modelId: runner.loadedModel?.id,
      isStreaming: true,
    );
    _appendMessage(assistantMsg);
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.generating;

    // 3. Stream tokens
    final prompt = _buildPrompt(state.messages, text.trim());
    final buffer = StringBuffer();
    final temperature = _ref.read(temperatureProvider);
    final topP = _ref.read(topPProvider);
    final maxTok = _ref.read(maxTokensProvider);
    final streamingTts = _ref.read(streamingTtsProvider);
    final autoSpeak = _ref.read(autoSpeakProvider);
    final voice = _ref.read(voiceServiceProvider);
    // Track which portion has already been sent to TTS so we don't repeat
    int _ttsSentUpTo = 0;

    try {
      await _tokenSub?.cancel();
      _tokenSub = runner.generate(prompt,
        temperature: temperature, topP: topP, maxTokens: maxTok).listen(
        (token) {
          buffer.write(token);
          _updateLastAssistantMessage(buffer.toString(), isStreaming: true);
          // Streaming TTS: speak each complete sentence as it arrives
          if (streamingTts && autoSpeak) {
            final text = buffer.toString();
            final unsent = text.substring(_ttsSentUpTo);
            final sentenceEnd = _lastSentenceBoundary(unsent);
            if (sentenceEnd > 0) {
              final chunk = unsent.substring(0, sentenceEnd).trim();
              if (chunk.isNotEmpty) voice.speak(chunk);
              _ttsSentUpTo += sentenceEnd;
            }
          }
        },
        onDone: () {
          final response = buffer.toString();
          _updateLastAssistantMessage(response, isStreaming: false);
          _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
          _maybeSetSessionTitle();
          _maybeSaveMemory();
          _scheduleCloudSave();
          if (autoSpeak) {
            if (streamingTts) {
              // Speak any trailing text not yet sent
              final remaining = response.substring(_ttsSentUpTo).trim();
              if (remaining.isNotEmpty) voice.speak(remaining);
            } else {
              voice.speak(response);
            }
          }
        },
        onError: (e) {
          _updateLastAssistantMessage(
            'Error: ${e.toString()}',
            isStreaming: false,
          );
          _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
          state = state.copyWith(error: e.toString());
        },
      );
    } catch (e) {
      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
      state = state.copyWith(error: e.toString());
    }
  }

  /// Returns the index just past the last sentence-ending punctuation in [s].
  static int _lastSentenceBoundary(String s) {
    const endings = {'.', '!', '?', '\n'};
    for (var i = s.length - 1; i >= 0; i--) {
      if (endings.contains(s[i])) return i + 1;
    }
    return 0;
  }

  /// Edit a user message in-place and re-run generation from that point.
  Future<void> editAndRegenerate(String messageId, String newContent) async {
    final session = state.activeSession;
    if (session == null) return;

    final idx = session.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;

    // Truncate history from that message onward, replace content
    final updated = session.messages.sublist(0, idx);
    final newSession = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: session.title,
      modelId: session.modelId,
      messages: updated,
    );
    state = state.copyWith(
      sessions: state.sessions
          .map((s) => s.id == session.id ? newSession : s)
          .toList(),
    );
    await send(newContent);
  }

  void stopGeneration() {
    _ref.read(llamaRunnerProvider).cancelGeneration();
    _tokenSub?.cancel();
    _tokenSub = null;
    _updateLastAssistantMessage(
      _lastAssistantContent(),
      isStreaming: false,
    );
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
  }

  /// Appends a plain assistant text message without invoking the LLM.
  void replyWithText(String text) {
    if (state.activeSession == null) newChat();
    _appendMessage(ChatMessage(
      id: _uid(),
      role: MessageRole.assistant,
      content: text,
      timestamp: DateTime.now(),
    ));
    _maybeSetSessionTitle();
  }

  /// Appends a finished assistant message containing a generated attachment.
  void sendGeneratedAttachment({
    required String caption,
    required ChatAttachment attachment,
  }) {
    if (state.activeSession == null) newChat();
    final msg = ChatMessage(
      id: _uid(),
      role: MessageRole.assistant,
      content: caption,
      timestamp: DateTime.now(),
      modelId: null,
      attachments: [attachment],
    );
    _appendMessage(msg);
    _maybeSetSessionTitle();
  }

  // ── Siri-specific: generate without a UI session ──────────────────────────

  /// Used by SiriService to get a spoken answer without touching chat state.
  Future<String> generateForSiri(String question) async {
    final runner = _ref.read(llamaRunnerProvider);
    if (runner.status != LlamaStatus.ready) {
      return 'PintSizeAi is not ready. Please open the app to load a model first.';
    }

    final prompt = _buildSiriPrompt(question);
    final buffer = StringBuffer();

    await for (final token in runner.generate(prompt, maxTokens: 200)) {
      buffer.write(token);
    }

    return buffer.toString().trim();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _appendMessage(ChatMessage msg) {
    final session = state.activeSession;
    if (session == null) return;

    final updated = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: session.title,
      modelId: session.modelId,
      messages: [...session.messages, msg],
    );

    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
  }

  void _updateLastAssistantMessage(String content, {required bool isStreaming}) {
    final session = state.activeSession;
    if (session == null) return;

    final messages = session.messages.toList();
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) {
        messages[i] = messages[i].copyWith(
          content: content,
          isStreaming: isStreaming,
        );
        break;
      }
    }

    final updated = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: session.title,
      modelId: session.modelId,
      messages: messages,
    );

    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
  }

  String _lastAssistantContent() {
    final msgs = state.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].isAssistant) return msgs[i].content;
    }
    return '';
  }

  void _maybeSetSessionTitle() {
    final session = state.activeSession;
    if (session == null || session.title != null) return;
    final userMsgs = session.messages.where((m) => m.isUser).toList();
    final assistantMsgs = session.messages.where((m) => m.isAssistant && !m.isStreaming).toList();
    if (userMsgs.isEmpty) return;

    // After the first real exchange, generate a smart title via the model.
    // Fall back to the first message text if no model is loaded.
    if (userMsgs.length >= 1 && assistantMsgs.isNotEmpty) {
      _generateTitle(session);
    }
  }

  Future<void> _generateTitle(ChatSession session) async {
    final runner = _ref.read(llamaRunnerProvider);
    if (runner.status != LlamaStatus.ready) {
      // Fallback: use first user message
      _setTitle(session, session.messages.where((m) => m.isUser).first.content);
      return;
    }

    // Build a minimal prompt asking for a 3-5 word title
    final exchange = session.messages
        .where((m) => !m.isStreaming)
        .take(4)
        .map((m) => '${m.isUser ? "User" : "Assistant"}: ${m.content}')
        .join('\n');

    final titlePrompt =
        '<|im_start|>system\nYou are a title generator. '
        'Reply with ONLY a short title of 3 to 5 words. No quotes, no punctuation at the end.<|im_end|>\n'
        '<|im_start|>user\nSummarize this conversation in 3-5 words:\n$exchange<|im_end|>\n'
        '<|im_start|>assistant\n';

    try {
      final buffer = StringBuffer();
      await for (final tok in runner.generate(titlePrompt, maxTokens: 20, temperature: 0.3)) {
        buffer.write(tok);
        if (buffer.length > 60) break;
      }
      final raw = buffer.toString().trim();
      if (raw.isNotEmpty) {
        _setTitle(session, raw);
        return;
      }
    } catch (_) {
      // ignored — fall through to fallback
    }
    _setTitle(session, session.messages.where((m) => m.isUser).first.content);
  }

  /// After the 6th message, generate a 1-sentence memory and persist it.
  Future<void> _maybeSaveMemory() async {
    final session = state.activeSession;
    if (session == null) return;
    final msgs = session.messages.where((m) => !m.isStreaming).toList();
    if (msgs.length < 6) return;

    final runner = _ref.read(llamaRunnerProvider);
    if (runner.status != LlamaStatus.ready) return;

    final exchange = msgs
        .take(6)
        .map((m) => '${m.isUser ? "User" : "AI"}: ${m.content.substring(0, m.content.length.clamp(0, 120))}')
        .join('\n');

    const memPrompt =
        '<|im_start|>system\nYou write one-sentence memory summaries.<|im_end|>\n'
        '<|im_start|>user\nSummarise this in ONE sentence for future reference:\n';

    try {
      final buf = StringBuffer();
      await for (final tok
          in runner.generate('$memPrompt$exchange<|im_end|>\n<|im_start|>assistant\n',
              maxTokens: 40, temperature: 0.3)) {
        buf.write(tok);
        if (buf.length > 200) break;
      }
      final summary = buf.toString().trim();
      if (summary.isNotEmpty) {
        _ref.read(persistentMemoriesProvider.notifier).add(summary);
        await _ref.read(settingsServiceProvider).addMemory(summary);
      }
    } catch (_) {
      // Best-effort — don't crash if summary fails
    }
  }

  void _setTitle(ChatSession session, String raw) {
    // Re-fetch session to avoid stale reference
    final current = state.sessions.where((s) => s.id == session.id).firstOrNull;
    if (current == null || current.title != null) return;

    final clean = raw.replaceAll(RegExp(r'["""''\n]'), '').trim();
    final title = clean.length > 50 ? '${clean.substring(0, 50)}…' : clean;
    final updated = ChatSession(
      id: current.id,
      createdAt: current.createdAt,
      title: title,
      modelId: current.modelId,
      messages: current.messages,
    );
    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
  }

  /// Builds the full inference prompt, applying the correct chat template
  /// for the loaded model's family.
  ///
  ///  • Llama 3.x → Llama 3 header format   (<|start_header_id|>…)
  ///  • Everything else → ChatML             (<|im_start|>…)
  ///
  /// ChatML works for SmolLM2, Qwen 2.x, Gemma 3, Phi-4, DeepSeek-R1,
  /// Mistral and most other instruction-tuned models in the catalogue.
  String _buildPrompt(List<ChatMessage> history, String latestUser) {
    final family = _ref.read(llamaRunnerProvider).loadedModel?.family ?? '';
    return family == 'llama'
        ? _buildLlama3Prompt(history)
        : _buildChatMLPrompt(history);
  }

  // ── ChatML (default — works for SmolLM2, Qwen, Gemma, Phi, DeepSeek…) ─────

  String _buildChatMLPrompt(List<ChatMessage> history) {
    final customPrompt = _ref.read(customSystemPromptProvider);
    final memories = _ref.read(persistentMemoriesProvider);

    final defaultSystem =
        'You are PintSizeAi, a private on-device AI assistant. '
        'You are helpful, concise, and honest. '
        'Everything you generate runs locally on the user\'s device — '
        'no data ever leaves the phone.';

    var system = customPrompt ?? defaultSystem;
    if (memories.isNotEmpty) {
      system +=
          '\n\nMemory from past conversations:\n${memories.take(5).map((m) => '- $m').join('\n')}';
    }

    final buf = StringBuffer();
    buf.write('<|im_start|>system\n$system<|im_end|>\n');

    for (final msg in history.where((m) => !m.isStreaming || m.isUser)) {
      final role = msg.isUser ? 'user' : 'assistant';
      buf.write('<|im_start|>$role\n${msg.content}<|im_end|>\n');
    }

    buf.write('<|im_start|>assistant\n');
    return buf.toString();
  }

  // ── Llama 3 format (Llama 3.2 1B/3B, Llama 3.3 8B, Llama 3.1 8B) ─────────

  String _buildLlama3Prompt(List<ChatMessage> history) {
    const system =
        'You are PintSizeAi, a private on-device AI assistant. '
        'You are helpful, concise, and honest. '
        'Everything you generate runs locally on the user\'s device — '
        'no data ever leaves the phone.';

    final buf = StringBuffer();
    buf.write('<|begin_of_text|>');
    buf.write('<|start_header_id|>system<|end_header_id|>\n$system<|eot_id|>');

    for (final msg in history.where((m) => !m.isStreaming || m.isUser)) {
      final role = msg.isUser ? 'user' : 'assistant';
      buf.write('<|start_header_id|>$role<|end_header_id|>\n${msg.content}<|eot_id|>');
    }

    buf.write('<|start_header_id|>assistant<|end_header_id|>\n');
    return buf.toString();
  }

  // ── Siri prompts (always ChatML — Siri always uses the loaded model) ────────

  String _buildSiriPrompt(String question) {
    const system =
        'You are PintSizeAi, answering a Siri voice question. '
        'Reply in 1-3 plain sentences, no bullet points, no markdown. '
        'Be direct and concise — your answer will be spoken aloud.';
    return '<|im_start|>system\n$system<|im_end|>\n'
        '<|im_start|>user\n$question<|im_end|>\n'
        '<|im_start|>assistant\n';
  }

  String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
      (DateTime.now().millisecond % 1000).toString();

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }
}
