// Pure-Dart tests for model fit + capability inference and helpers.
// Run with: flutter test test/features/models/

import 'package:flutter_test/flutter_test.dart';
import 'package:pintsize_ai/features/device_recommender/device_profile.dart';
import 'package:pintsize_ai/features/device_recommender/model_catalogue.dart';
import 'package:pintsize_ai/features/models/model_fit.dart';
import 'package:pintsize_ai/features/web_search/stock_service.dart';
import 'package:pintsize_ai/features/documents/document_retrieval_service.dart';
import 'package:pintsize_ai/features/models/huggingface_service.dart';

ModelVariant _model({
  required double params,
  required int ramBytes,
  String id = 'test',
  String name = 'Test Model',
  bool multimodal = false,
  bool reasoning = false,
  List<String> strengths = const [],
}) =>
    ModelVariant(
      id: id,
      displayName: name,
      family: ModelFamily.llama,
      parametersBillions: params,
      quant: Quant.q4km,
      fileSizeBytes: ramBytes,
      ramRequiredBytes: ramBytes,
      contextLength: 4096,
      downloadUrl: 'https://example.com/m.gguf',
      strengths: strengths,
      isMultimodal: multimodal,
      isReasoningModel: reasoning,
    );

DeviceProfile _device(int totalGb) => DeviceProfile(
      totalRamBytes: totalGb * 1000000000,
      freeRamBytes: (totalGb * 1000000000 * 0.6).round(),
      freeStorageBytes: 50 * 1000000000,
      chipTier: ChipTier.highEnd,
      cpuCoreCount: 6,
      hasGpuAcceleration: false,
      deviceName: 'Test iPhone',
      osVersion: '18.0',
    );

void main() {
  group('deviceFit', () {
    final device = _device(8); // budget = 8GB * 0.5 = 4GB
    test('small model is a great fit', () {
      final fit = deviceFit(_model(params: 1, ramBytes: 1000000000), device);
      expect(fit, ModelFit.great);
    });
    test('mid model is good/tight', () {
      final fit = deviceFit(_model(params: 7, ramBytes: 3800000000), device);
      expect(fit == ModelFit.good || fit == ModelFit.tight, isTrue);
    });
    test('huge model is too big', () {
      final fit = deviceFit(_model(params: 70, ramBytes: 40000000000), device);
      expect(fit, ModelFit.tooBig);
    });
  });

  group('capabilityTags', () {
    test('detects coding + chat from name', () {
      final tags = capabilityTags(_model(
          params: 3, ramBytes: 2000000000, name: 'Qwen2.5 Coder Instruct'));
      expect(tags, contains('Coding'));
      expect(tags, contains('Chat'));
    });
    test('detects vision for multimodal', () {
      final tags = capabilityTags(
          _model(params: 8, ramBytes: 5000000000, multimodal: true));
      expect(tags, contains('Vision'));
    });
    test('flags tiny models as fast', () {
      final tags = capabilityTags(_model(params: 1, ramBytes: 800000000));
      expect(tags, contains('Fast & light'));
    });
  });

  group('StockService.cleanQuery', () {
    test('strips filler words to the company', () {
      expect(
          StockService.cleanQuery('what is the spacex share price'), 'spacex');
      expect(StockService.cleanQuery('tesla stock price'), 'tesla');
      expect(StockService.cleanQuery('current price of aapl'), 'aapl');
    });
    test('handles apostrophes without leaving a stray token', () {
      expect(
          StockService.cleanQuery("what's the spacex share price"), 'spacex');
      expect(StockService.cleanQuery('what’s tesla trading at'), 'tesla');
    });
    test('keeps ticker with exchange suffix', () {
      expect(StockService.cleanQuery('share price of ghhf.asx'), 'ghhf.asx');
    });
  });

  group('StockService.looksLikeStockQuery', () {
    test('true for price questions', () {
      expect(StockService.looksLikeStockQuery('tesla stock price'), isTrue);
      expect(
          StockService.looksLikeStockQuery('what is aapl trading at'), isTrue);
    });
    test('false for ordinary chat', () {
      expect(StockService.looksLikeStockQuery('write hello world in python'),
          isFalse);
    });
  });

  group('HuggingFace parsing', () {
    test('quant label parsed from filename', () {
      const f =
          HFFile(path: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf', sizeBytes: 100);
      expect(f.quantLabel, 'Q4_K_M');
    });
    test('toModelVariant infers params, family, url', () {
      const repo = HFRepo(
        id: 'bartowski/Qwen2.5-3B-Instruct-GGUF',
        downloads: 1000,
        likes: 50,
        lastModified: '2025-01-01',
        tags: ['gguf'],
      );
      const file = HFFile(
          path: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf', sizeBytes: 2000000000);
      final m = HuggingFaceService.toModelVariant(repo, file);
      expect(m.parametersBillions, 3.0);
      expect(m.family, ModelFamily.qwen);
      expect(m.downloadUrl, contains('resolve/main'));
      expect(m.id.startsWith('hf_'), isTrue);
    });
  });

  group('DocumentRetrievalService', () {
    test('short doc returned unchanged', () {
      final svc = DocumentRetrievalService();
      const doc = 'A short note about cats.';
      expect(svc.relevantContext(doc, 'cats'), doc);
    });
    test('long doc returns the relevant passage', () {
      final svc =
          DocumentRetrievalService(chunkSize: 200, overlap: 20, topK: 1);
      final filler =
          List.filled(60, 'The weather is mild and pleasant.').join(' ');
      final needle = 'The quarterly revenue for Acme was 42 million dollars.';
      final doc = '$filler $needle $filler';
      final result = svc.relevantContext(doc, 'Acme revenue quarterly');
      expect(result.contains('Acme'), isTrue);
      expect(result.length, lessThan(doc.length));
    });
  });
}
