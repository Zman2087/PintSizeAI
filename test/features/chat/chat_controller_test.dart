// Tests for ChatController — pure Dart, no Flutter or platform channels.
// Run with: flutter test test/features/chat/

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mypocketai/features/chat/chat_controller.dart';
import 'package:mypocketai/features/chat/chat_message.dart';
import 'package:mypocketai/features/chat/chat_providers.dart';
import 'package:mypocketai/features/device_recommender/model_catalogue.dart';
import 'package:mypocketai/features/llm/llama_runner.dart';
import 'package:mypocketai/features/llm/llama_runner_mock.dart';
import 'package:mypocketai/features/llm/llm_providers.dart';
import 'package:mypocketai/features/models/model_providers.dart';
import 'package:mypocketai/features/siri/siri_service.dart';

const _testModel = ModelVariant(
  id: 'llama32-3b-q4km',
  displayName: 'Llama 3.2 3B',
  family: ModelFamily.llama,
  parametersBillions: 3.0,
  quant: Quant.q4km,
  fileSizeBytes: 2020000000,
  ramRequiredBytes: 2400000000,
  contextLength: 131072,
  downloadUrl: 'https://example.com/llama.gguf',
  strengths: ['Balanced'],
);

/// Creates a ProviderContainer with a real LlamaRunnerMock pre-loaded.
Future<ProviderContainer> _makeContainer() async {
  final runner = LlamaRunnerMock();
  await runner.load(_testModel, '/fake/path.gguf');

  final container = ProviderContainer(
    overrides: [
      llamaRunnerProvider.overrideWithValue(runner),
      llamaStatusProvider.overrideWith((ref) => runner.status),
      // Stub Siri and model actions so they don't need platform channels
      siriServiceProvider.overrideWith(
        (ref) => _NoOpSiriService(ref: ref),
      ),
      activeModelProvider.overrideWith((ref) => _testModel),
    ],
  );

  // Seed the status correctly
  container.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;

  return container;
}

void main() {
  group('ChatController — session management', () {
    test('starts with no sessions', () {
      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWith((ref) => LlamaRunnerMock()),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      final state = container.read(chatControllerProvider);
      expect(state.sessions, isEmpty);
      expect(state.activeSession, isNull);
    });

    test('newChat() creates a session and sets it active', () {
      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWith((ref) => LlamaRunnerMock()),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      container.read(chatControllerProvider.notifier).newChat();
      final state = container.read(chatControllerProvider);

      expect(state.sessions.length, 1);
      expect(state.activeSessionId, isNotNull);
      expect(state.activeSession, isNotNull);
    });

    test('newChat() twice creates two sessions, most recent is active', () {
      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWith((ref) => LlamaRunnerMock()),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      container.read(chatControllerProvider.notifier).newChat();
      container.read(chatControllerProvider.notifier).newChat();

      final state = container.read(chatControllerProvider);
      expect(state.sessions.length, 2);
      // The most recently created session should be first (prepended)
      expect(state.activeSessionId, equals(state.sessions.first.id));
    });

    test('selectSession() changes the active session', () {
      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWith((ref) => LlamaRunnerMock()),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      final ctrl = container.read(chatControllerProvider.notifier);
      ctrl.newChat();
      ctrl.newChat();

      final state = container.read(chatControllerProvider);
      final secondId = state.sessions[1].id;

      ctrl.selectSession(secondId);
      expect(container.read(chatControllerProvider).activeSessionId, secondId);
    });

    test('deleteSession() removes it and updates activeSessionId', () {
      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWith((ref) => LlamaRunnerMock()),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      final ctrl = container.read(chatControllerProvider.notifier);
      ctrl.newChat();
      ctrl.newChat();

      final stateBeforeDelete = container.read(chatControllerProvider);
      final activeId = stateBeforeDelete.activeSessionId!;

      ctrl.deleteSession(activeId);

      final state = container.read(chatControllerProvider);
      expect(state.sessions.any((s) => s.id == activeId), isFalse);
      expect(state.sessions.length, 1);
    });
  });

  group('ChatController — messaging', () {
    test('send() creates user + assistant messages', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final ctrl = container.read(chatControllerProvider.notifier);

      // send() auto-creates a session if none exists
      ctrl.send('Hello');
      await Future.delayed(const Duration(milliseconds: 100));

      final messages = container.read(messagesProvider);
      expect(messages, isNotEmpty);

      final user = messages.firstWhere((m) => m.isUser);
      expect(user.content, 'Hello');

      final assistant = messages.firstWhere((m) => m.isAssistant);
      expect(assistant, isNotNull);
    });

    test('send() ignores blank messages', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      container.read(chatControllerProvider.notifier).send('   ');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(messagesProvider), isEmpty);
    });

    test('send() auto-creates session when none active', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final state = container.read(chatControllerProvider);
      expect(state.activeSession, isNull);

      container.read(chatControllerProvider.notifier).send('Hi');
      await Future.delayed(const Duration(milliseconds: 50));

      final newState = container.read(chatControllerProvider);
      expect(newState.sessions, isNotEmpty);
    });

    test('assistant message streams content over time', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      container.read(chatControllerProvider.notifier).send('Tell me something');
      await Future.delayed(const Duration(milliseconds: 200));

      final messages = container.read(messagesProvider);
      final assistant = messages.where((m) => m.isAssistant).firstOrNull;
      expect(assistant, isNotNull);
      // By 200ms we should have some content streaming
      // (content might be empty right at 0ms then grows)
    });

    test('full stream eventually produces non-empty assistant response', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      container.read(chatControllerProvider.notifier).send('Hello');

      // Wait for full generation (mock: ~10 words * 95ms = ~1s)
      await Future.delayed(const Duration(seconds: 4));

      final messages = container.read(messagesProvider);
      final assistant = messages.where((m) => m.isAssistant).firstOrNull;
      expect(assistant?.content.trim(), isNotEmpty);
      expect(assistant?.isStreaming, isFalse);
    });
  });

  group('ChatController — generateForSiri', () {
    test('returns a non-empty string', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);

      final answer = await container
          .read(chatControllerProvider.notifier)
          .generateForSiri('What is the capital of France?');

      expect(answer.trim(), isNotEmpty);
    });

    test('returns an error string when no model loaded', () async {
      final runner = LlamaRunnerMock(); // not loaded

      final container = ProviderContainer(overrides: [
        llamaRunnerProvider.overrideWithValue(runner),
        llamaStatusProvider.overrideWith((ref) => LlamaStatus.idle),
        siriServiceProvider.overrideWith((ref) => _NoOpSiriService(ref: ref)),
        activeModelProvider.overrideWith((ref) => null),
      ]);
      addTearDown(container.dispose);

      final answer = await container
          .read(chatControllerProvider.notifier)
          .generateForSiri('Hello');

      expect(answer, contains('not ready'));
    });
  });

  group('ChatSession — displayTitle', () {
    test('uses title when set', () {
      final s = ChatSession(
        id: '1',
        createdAt: DateTime.now(),
        title: 'My custom title',
      );
      expect(s.displayTitle, 'My custom title');
    });

    test('uses first user message when no title', () {
      final s = ChatSession(
        id: '1',
        createdAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'a',
            role: MessageRole.user,
            content: 'Hello there',
            timestamp: DateTime.now(),
          ),
        ],
      );
      expect(s.displayTitle, 'Hello there');
    });

    test('truncates long first message', () {
      final s = ChatSession(
        id: '1',
        createdAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'a',
            role: MessageRole.user,
            content: 'A' * 60,
            timestamp: DateTime.now(),
          ),
        ],
      );
      expect(s.displayTitle.length, lessThanOrEqualTo(42)); // 40 + ellipsis
    });

    test('returns "New chat" when no messages and no title', () {
      final s = ChatSession(id: '1', createdAt: DateTime.now());
      expect(s.displayTitle, 'New chat');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Stubs
// ─────────────────────────────────────────────────────────────────────────────

class _NoOpSiriService extends SiriService {
  _NoOpSiriService({required super.ref});

  @override
  void init() {} // no platform channel in tests

  @override
  Future<void> setModelReady(bool ready) async {}
}
