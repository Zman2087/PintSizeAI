import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../attachments/attachment.dart';
import '../device_recommender/model_catalogue.dart';
import '../llm/llama_runner.dart';
import '../llm/llm_providers.dart';
import '../models/model_providers.dart';
import '../settings/settings_providers.dart';
import '../settings/settings_service.dart';
import '../sync/cloud_sync_service.dart';
import '../voice/voice_providers.dart';
import '../diagnostics/diag_log.dart';
import 'chat_message.dart';
import 'chat_persistence_service.dart';

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
      : super(const ChatState(sessions: [], activeSessionId: null)) {
    _restoreLocal();
  }

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;
  final _cloudSync = CloudSyncService();
  final _persistence = ChatPersistenceService();

  // Debounced local persistence — keeps disk writes off the hot path.
  Timer? _localSaveTimer;
  bool _restored = false;

  /// Loads saved sessions from disk on startup (best-effort).
  Future<void> _restoreLocal() async {
    final saved = await _persistence.load();
    _restored = true;
    if (saved == null || saved.sessions.isEmpty) return;
    // Don't clobber anything created before restore finished.
    if (state.sessions.isNotEmpty) return;
    state = state.copyWith(
      sessions: saved.sessions,
      activeSessionId:
          saved.activeSessionId ?? saved.sessions.first.id,
    );
  }

  /// Debounced save of all sessions to local disk.
  void _persistLocal() {
    if (!_restored) return; // avoid overwriting before initial load completes
    _localSaveTimer?.cancel();
    _localSaveTimer = Timer(const Duration(milliseconds: 600), () {
      _persistence.save(state.sessions, state.activeSessionId);
    });
  }

  // Debounced cloud save — wait 3s after last change to avoid thrashing
  Timer? _syncTimer;
  void _scheduleCloudSave() {
    _persistLocal(); // always keep a local copy too
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
    Uint8List? imageBytes, // raw image for multimodal (vision) models
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

    // Auto-create a session if none is active
    if (state.activeSession == null) newChat();

    var runner = _ref.read(llamaRunnerProvider);
    if (runner.status != LlamaStatus.ready) {
      // The model may have been evicted under memory pressure (e.g. iOS freed
      // it while the app was backgrounded). Try to silently reload it.
      final active = _ref.read(activeModelProvider);
      if (active != null) {
        try {
          await _ref.read(modelActionsProvider).loadModel(active);
        } catch (_) {}
        runner = _ref.read(llamaRunnerProvider);
      }
      if (runner.status != LlamaStatus.ready) {
        state = state.copyWith(
          error: 'No model loaded. Open the model picker to choose one.',
        );
        return;
      }
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
    final prompt = await _buildPrompt(state.messages);
    final buffer = StringBuffer();
    final temperature = _ref.read(temperatureProvider);
    final topP = _ref.read(topPProvider);
    final maxTok = _ref.read(maxTokensProvider);
    final streamingTts = _ref.read(streamingTtsProvider);
    final autoSpeak = _ref.read(autoSpeakProvider);
    final voice = _ref.read(voiceServiceProvider);
    // Track which portion has already been sent to TTS so we don't repeat
    int ttsSentUpTo = 0;
    // Generation timing for tokens/sec reporting.
    final genStart = DateTime.now();
    var tokenCount = 0;
    var finished = false;

    // Finalises the response exactly once: strips any chat-template stop marker,
    // updates the message, persists, and speaks (if enabled).
    void finalize(String raw) {
      if (finished) return;
      finished = true;

      // Cut at the earliest stop marker the model may have emitted.
      var clean = raw;
      var cutAt = clean.length;
      for (final s in _kStopSequences) {
        final i = clean.indexOf(s);
        if (i >= 0 && i < cutAt) cutAt = i;
      }
      clean = clean.substring(0, cutAt).trimRight();

      final elapsedMs = DateTime.now().difference(genStart).inMilliseconds;
      final tps = elapsedMs > 0 ? tokenCount * 1000 / elapsedMs : 0.0;
      DiagLog.log('response tokens=$tokenCount tps=${tps.toStringAsFixed(1)} '
          'autoSpeak=$autoSpeak first120="${clean.length > 120 ? clean.substring(0, 120) : clean}"');
      _updateLastAssistantMessage(
        clean,
        isStreaming: false,
        tokensPerSec: tps,
        elapsedMs: elapsedMs,
      );
      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
      _maybeSetSessionTitle();
      _maybeSaveMemory();
      _persistLocal();
      _scheduleCloudSave();
      if (autoSpeak) {
        if (streamingTts) {
          final remaining = clean.length > ttsSentUpTo
              ? clean.substring(ttsSentUpTo).trim()
              : '';
          if (remaining.isNotEmpty) voice.speak(remaining);
        } else {
          voice.speak(clean);
        }
      }
    }

    try {
      await _tokenSub?.cancel();
      _tokenSub = runner.generate(prompt,
        temperature: temperature, topP: topP, maxTokens: maxTok,
        imageBytes: imageBytes).listen(
        (token) {
          if (finished) return;
          tokenCount++;
          buffer.write(token);
          final current = buffer.toString();

          // Stop-sequence detection: many GGUFs don't tag their turn-end token
          // as EOG, so the model would otherwise role-play both sides forever.
          var stopIdx = -1;
          for (final s in _kStopSequences) {
            final i = current.indexOf(s);
            if (i >= 0 && (stopIdx < 0 || i < stopIdx)) stopIdx = i;
          }
          if (stopIdx >= 0) {
            _tokenSub?.cancel();
            runner.cancelGeneration();
            finalize(current);
            return;
          }

          _updateLastAssistantMessage(current, isStreaming: true);
          // Streaming TTS: speak each complete sentence as it arrives
          if (streamingTts && autoSpeak) {
            final unsent = current.substring(ttsSentUpTo);
            final sentenceEnd = _lastSentenceBoundary(unsent);
            if (sentenceEnd > 0) {
              final chunk = unsent.substring(0, sentenceEnd).trim();
              if (chunk.isNotEmpty) voice.speak(chunk);
              ttsSentUpTo += sentenceEnd;
            }
          }
        },
        onDone: () => finalize(buffer.toString()),
        onError: (e) {
          if (finished) return;
          finished = true;
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

  /// Chat-template turn markers that signal the model has finished its reply.
  static const _kStopSequences = [
    '<|im_end|>',
    '<|im_start|>',
    '<|eot_id|>',
    '<|start_header_id|>',
    '<|end_of_text|>',
    '<|endoftext|>',
    '</s>',
    '<end_of_turn>',
  ];

  /// Returns the index just past the last sentence-ending punctuation in [s].
  static int _lastSentenceBoundary(String s) {
    const endings = {'.', '!', '?', '\n'};
    for (var i = s.length - 1; i >= 0; i--) {
      if (endings.contains(s[i])) return i + 1;
    }
    return 0;
  }

  /// Fork the active session at [messageIndex], creating a new session that
  /// starts with all messages up to (and including) that index. The new
  /// session becomes active so the user can explore an alternate path.
  void branchAt(int messageIndex) {
    final session = state.activeSession;
    if (session == null) return;

    final history = session.messages.take(messageIndex + 1).toList();
    final branchSession = ChatSession(
      id: _uid(),
      createdAt: DateTime.now(),
      title: '${session.displayTitle} (branch)',
      branchedFromSessionId: session.id,
      branchedAtMessageIndex: messageIndex,
      messages: history.map((m) => m.copyWith()).toList(),
    );
    state = state.copyWith(
      sessions: [branchSession, ...state.sessions],
      activeSessionId: branchSession.id,
    );
    _scheduleCloudSave();
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

  /// Re-answers the most recent user prompt using [model], loading it first.
  Future<void> regenerateWithModel(ModelVariant model) async {
    final session = state.activeSession;
    if (session == null) return;

    // Find the last user message.
    String? lastUserId;
    String lastUserContent = '';
    for (var i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].isUser) {
        lastUserId = session.messages[i].id;
        lastUserContent = session.messages[i].content;
        break;
      }
    }
    if (lastUserId == null) return;

    try {
      await _ref.read(modelActionsProvider).loadModel(model);
    } catch (_) {
      state = state.copyWith(error: 'Could not load ${model.displayName}.');
      return;
    }
    await editAndRegenerate(lastUserId, lastUserContent);
  }

  /// Renames a session. Pass null/empty to clear the custom title.
  void renameSession(String sessionId, String? title) {
    final trimmed = title?.trim();
    state = state.copyWith(
      sessions: state.sessions.map((s) {
        if (s.id != sessionId) return s;
        s.title = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
        return s;
      }).toList(),
    );
    _scheduleCloudSave();
  }

  /// Toggles whether a session is pinned to the top of the history list.
  void togglePin(String sessionId) {
    state = state.copyWith(
      sessions: state.sessions.map((s) {
        if (s.id == sessionId) s.pinned = !s.pinned;
        return s;
      }).toList(),
    );
    _scheduleCloudSave();
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
      pinned: session.pinned,
      branchedFromSessionId: session.branchedFromSessionId,
      branchedAtMessageIndex: session.branchedAtMessageIndex,
      messages: [...session.messages, msg],
    );

    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
    _persistLocal();
  }

  /// Sets the like/dislike rating on a message. 1 = like, -1 = dislike, 0 clears.
  void rateMessage(String messageId, int rating) {
    final session = state.activeSession;
    if (session == null) return;
    final messages = session.messages.toList();
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final wasDisliked = messages[idx].rating == -1;
    messages[idx].rating = rating == 0 ? null : rating;
    final updated = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: session.title,
      modelId: session.modelId,
      pinned: session.pinned,
      branchedFromSessionId: session.branchedFromSessionId,
      branchedAtMessageIndex: session.branchedAtMessageIndex,
      messages: messages,
    );
    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
    _persistLocal();

    // A thumbs-down becomes a memory so future answers avoid the same mistake.
    if (rating == -1 && !wasDisliked) {
      _recordDislikeFeedback(messages, idx);
    }
  }

  /// Stores a concise note about a disliked answer in persistent memory, which
  /// is injected into future system prompts.
  void _recordDislikeFeedback(List<ChatMessage> messages, int assistantIdx) {
    // Find the user question that prompted the disliked reply.
    String question = '';
    for (var i = assistantIdx - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        question = messages[i].content;
        break;
      }
    }
    String trim(String s, int n) =>
        s.length > n ? '${s.substring(0, n).trim()}…' : s.trim();

    if (!_ref.read(memoryEnabledProvider)) return;

    final note = question.isNotEmpty
        ? 'The user disliked a previous answer to: "${trim(question, 120)}". '
            'Give a more accurate, helpful, directly-relevant answer to similar questions.'
        : 'The user disliked a previous answer. Be more accurate, concise and directly relevant.';

    _ref.read(persistentMemoriesProvider.notifier).add(note);
    _ref.read(settingsServiceProvider).addMemory(note);
  }

  void _updateLastAssistantMessage(
    String content, {
    required bool isStreaming,
    double? tokensPerSec,
    int? elapsedMs,
  }) {
    final session = state.activeSession;
    if (session == null) return;

    final messages = session.messages.toList();
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) {
        messages[i] = messages[i].copyWith(
          content: content,
          isStreaming: isStreaming,
          tokensPerSec: tokensPerSec,
          elapsedMs: elapsedMs,
        );
        break;
      }
    }

    final updated = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: session.title,
      modelId: session.modelId,
      pinned: session.pinned,
      branchedFromSessionId: session.branchedFromSessionId,
      branchedAtMessageIndex: session.branchedAtMessageIndex,
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
    if (!_ref.read(memoryEnabledProvider)) return;
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
  Future<String> _buildPrompt(List<ChatMessage> history) async {
    final runner = _ref.read(llamaRunnerProvider);

    // Build the message list (system + visible turns).
    final customPrompt = _ref.read(customSystemPromptProvider);
    final memories = _ref.read(persistentMemoriesProvider);
    final defaultSystem =
        'You are PintSizeAi, a private on-device AI assistant. '
        'You are helpful, concise, and honest. '
        'Everything you generate runs locally on the user\'s device — '
        'no data ever leaves the phone.';
    final memoryOn = _ref.read(memoryEnabledProvider);
    var system = customPrompt ?? defaultSystem;
    if (memoryOn && memories.isNotEmpty) {
      system +=
          '\n\nMemory from past conversations:\n${memories.take(5).map((m) => '- $m').join('\n')}';
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];
    for (final msg in history.where((m) => !m.isStreaming || m.isUser)) {
      messages.add({
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    // Prefer the model's own chat template (correct for every family); fall
    // back to ChatML if the model has no embedded template.
    final native = await runner.applyChatTemplate(messages);
    final useNative = native != null && native.trim().isNotEmpty;
    DiagLog.log('template=${useNative ? "NATIVE" : "chatml-fallback"} '
        'model=${runner.loadedModel?.id} family=${runner.loadedModel?.family} '
        'msgs=${messages.length}');
    if (useNative) return native;
    return _buildChatMLPrompt(system, history);
  }

  // ── ChatML fallback (SmolLM2, Qwen… ) ─────────────────────────────────────

  String _buildChatMLPrompt(String system, List<ChatMessage> history) {
    final buf = StringBuffer();
    buf.write('<|im_start|>system\n$system<|im_end|>\n');

    for (final msg in history.where((m) => !m.isStreaming || m.isUser)) {
      final role = msg.isUser ? 'user' : 'assistant';
      buf.write('<|im_start|>$role\n${msg.content}<|im_end|>\n');
    }

    buf.write('<|im_start|>assistant\n');
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
