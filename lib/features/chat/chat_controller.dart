import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../attachments/attachment.dart';
import '../device_recommender/model_catalogue.dart';
import '../llm/llama_runner.dart';
import '../llm/llm_providers.dart';
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

    // 1. Add user message
    final userMsg = ChatMessage(
      id: _uid(),
      role: MessageRole.user,
      content: text.trim(),
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

    try {
      await _tokenSub?.cancel();
      _tokenSub = runner.generate(prompt).listen(
        (token) {
          buffer.write(token);
          _updateLastAssistantMessage(buffer.toString(), isStreaming: true);
        },
        onDone: () {
          _updateLastAssistantMessage(buffer.toString(), isStreaming: false);
          _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
          _maybeSetSessionTitle();
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
    if (userMsgs.isEmpty) return;

    final title = userMsgs.first.content;
    final updated = ChatSession(
      id: session.id,
      createdAt: session.createdAt,
      title: title.length > 40 ? '${title.substring(0, 40)}…' : title,
      modelId: session.modelId,
      messages: session.messages,
    );
    state = state.copyWith(
      sessions: state.sessions.map((s) => s.id == session.id ? updated : s).toList(),
    );
  }

  /// Builds a simple conversational prompt for llama.cpp instruct models.
  String _buildPrompt(List<ChatMessage> history, String latestUser) {
    final buf = StringBuffer();
    buf.writeln('<|begin_of_text|>');
    buf.writeln('<|start_header_id|>system<|end_header_id|>');
    buf.writeln(
      'You are PintSizeAi, a private on-device AI assistant. '
      'You are helpful, concise, and honest. '
      'Your responses are processed locally on the user\'s device — no data leaves the phone.',
    );
    buf.writeln('<|eot_id|>');

    for (final msg in history.where((m) => !m.isStreaming || m.isUser)) {
      final role = msg.isUser ? 'user' : 'assistant';
      buf.writeln('<|start_header_id|>$role<|end_header_id|>');
      buf.writeln(msg.content);
      buf.writeln('<|eot_id|>');
    }

    buf.writeln('<|start_header_id|>assistant<|end_header_id|>');
    return buf.toString();
  }

  String _buildSiriPrompt(String question) =>
      '<|begin_of_text|>'
      '<|start_header_id|>system<|end_header_id|>'
      'You are PintSizeAi, answering a Siri voice question. '
      'Reply in 1-3 plain sentences, no bullet points, no markdown. '
      'Be direct and concise — your answer will be spoken aloud.'
      '<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>'
      '$question'
      '<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>';

  String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
      (DateTime.now().millisecond % 1000).toString();

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }
}
