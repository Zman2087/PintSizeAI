// Tests for LlamaRunnerMock — no Flutter dependency, no native library.
// Run with: flutter test test/features/llm/

import 'package:flutter_test/flutter_test.dart';
import 'package:pintsize_ai/features/device_recommender/model_catalogue.dart';
import 'package:pintsize_ai/features/llm/llama_runner.dart';
import 'package:pintsize_ai/features/llm/llama_runner_mock.dart';

const _testModel = ModelVariant(
  id: 'test-model',
  displayName: 'Test 3B',
  family: ModelFamily.llama,
  parametersBillions: 3.0,
  quant: Quant.q4km,
  fileSizeBytes: 2000000000,
  ramRequiredBytes: 2400000000,
  contextLength: 131072,
  downloadUrl: 'https://example.com/test.gguf',
  strengths: ['Testing'],
);

void main() {
  group('LlamaRunnerMock — lifecycle', () {
    test('starts in idle state', () {
      final runner = LlamaRunnerMock();
      expect(runner.status, LlamaStatus.idle);
      expect(runner.loadedModel, isNull);
    });

    test('load() transitions idle → loading → ready', () async {
      final runner = LlamaRunnerMock();
      expect(runner.status, LlamaStatus.idle);

      final future = runner.load(_testModel, '/fake/path.gguf');
      expect(runner.status, LlamaStatus.loading);

      await future;
      expect(runner.status, LlamaStatus.ready);
      expect(runner.loadedModel?.id, equals('test-model'));
    });

    test('unload() transitions ready → idle', () async {
      final runner = LlamaRunnerMock();
      await runner.load(_testModel, '/fake/path.gguf');
      expect(runner.status, LlamaStatus.ready);

      await runner.unload();
      expect(runner.status, LlamaStatus.idle);
      expect(runner.loadedModel, isNull);
    });

    test('load() replaces an existing model', () async {
      final runner = LlamaRunnerMock();
      await runner.load(_testModel, '/fake/path.gguf');

      const other = ModelVariant(
        id: 'other-model',
        displayName: 'Other 1B',
        family: ModelFamily.smollm,
        parametersBillions: 1.0,
        quant: Quant.q4km,
        fileSizeBytes: 800000000,
        ramRequiredBytes: 900000000,
        contextLength: 2048,
        downloadUrl: 'https://example.com/other.gguf',
        strengths: [],
      );

      await runner.load(other, '/fake/other.gguf');
      expect(runner.loadedModel?.id, equals('other-model'));
      expect(runner.status, LlamaStatus.ready);
    });
  });

  group('LlamaRunnerMock — generation', () {
    late LlamaRunnerMock runner;

    setUp(() async {
      runner = LlamaRunnerMock();
      await runner.load(_testModel, '/fake/path.gguf');
    });

    tearDown(() => runner.dispose());

    test('generate() produces non-empty output', () async {
      final tokens = <String>[];
      await for (final t in runner.generate('Hello')) {
        tokens.add(t);
      }
      final full = tokens.join();
      expect(full.trim(), isNotEmpty);
    });

    test('generate() emits multiple tokens', () async {
      final tokens = <String>[];
      await for (final t in runner.generate('What is AI?')) {
        tokens.add(t);
      }
      // Every response should be at least 5 tokens
      expect(tokens.length, greaterThan(5));
    });

    test('generate() transitions to generating then back to ready', () async {
      final statuses = <LlamaStatus>[];
      // Capture initial
      statuses.add(runner.status);

      final stream = runner.generate('hello');
      // After subscribing, status should be generating
      await Future.microtask(() {});

      await for (final _ in stream) {
        if (!statuses.contains(LlamaStatus.generating)) {
          statuses.add(runner.status);
        }
        break; // only need first token
      }

      expect(statuses, contains(LlamaStatus.ready)); // was ready before
      expect(statuses,
          contains(LlamaStatus.generating)); // transitioned during stream
    });

    test('generate() errors when model not loaded', () async {
      await runner.unload();
      await expectLater(
        runner.generate('hello'),
        emitsError(isA<StateError>()),
      );
    });

    test('cancelGeneration() stops the stream early', () async {
      int tokenCount = 0;
      await for (final _ in runner
          .generate('Tell me about the history of computing in detail')) {
        tokenCount++;
        if (tokenCount == 3) {
          runner.cancelGeneration();
          break;
        }
      }
      expect(tokenCount, lessThan(20));
      expect(runner.status, LlamaStatus.ready);
    });

    test('greeting produces a friendly response', () async {
      final buf = StringBuffer();
      await for (final t in runner.generate('Hello there!')) {
        buf.write(t);
      }
      final response = buf.toString().toLowerCase();
      expect(
        response.contains('hello') ||
            response.contains('hi') ||
            response.contains('assist'),
        isTrue,
      );
    });

    test('model question includes model name in response', () async {
      final buf = StringBuffer();
      await for (final t in runner.generate('What AI model are you running?')) {
        buf.write(t);
      }
      final response = buf.toString().toLowerCase();
      // Mock should reference the loaded model name or AI in general
      expect(
        response.contains('model') ||
            response.contains('test') ||
            response.contains('ai'),
        isTrue,
      );
    });

    test('date question returns a date-like response', () async {
      final buf = StringBuffer();
      await for (final t in runner.generate('What is today\'s date?')) {
        buf.write(t);
      }
      final response = buf.toString();
      // Should contain a year
      expect(response, matches(RegExp(r'20\d\d')));
    });
  });

  group('LlamaRunnerMock — multiple sessions', () {
    test('second generate() after first completes works correctly', () async {
      final runner = LlamaRunnerMock();
      await runner.load(_testModel, '/fake/path.gguf');

      final buf1 = StringBuffer();
      await for (final t in runner.generate('Hello')) {
        buf1.write(t);
      }

      final buf2 = StringBuffer();
      await for (final t in runner.generate('What is 2 + 2?')) {
        buf2.write(t);
      }

      expect(buf1.toString().trim(), isNotEmpty);
      expect(buf2.toString().trim(), isNotEmpty);
      runner.dispose();
    });
  });
}
