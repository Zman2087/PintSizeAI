import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../device_recommender/model_catalogue.dart';
import '../diagnostics/diag_log.dart';
import '../llm/llama_runner.dart';
import '../llm/llm_providers.dart';
import '../settings/settings_providers.dart';
import '../siri/siri_service.dart';
import '../web_search/url_fetch_service.dart';
import 'model_download_service.dart';
import 'model_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// First-launch auto-download
// ─────────────────────────────────────────────────────────────────────────────

/// Triggers once on first launch. If no model is on disk, silently
/// downloads kStarterModelId (SmolLM2 135M, ~75 MB) and auto-loads it.
///
/// Skipped when the guided onboarding hasn't been completed yet — in that case
/// onboarding handles the (device-appropriate) model download instead, so we
/// don't waste bandwidth grabbing the tiny starter first.
final firstLaunchSetupProvider = FutureProvider<void>((ref) async {
  final settings = ref.read(settingsServiceProvider);
  if (!await settings.getOnboardingComplete()) return; // onboarding will handle it

  final storage = ref.read(modelStorageProvider);
  final downloaded = await storage.downloadedModelIds();
  if (downloaded.isNotEmpty) return; // already has a model

  final starter = kModelCatalogue.firstWhere((m) => m.id == kStarterModelId);
  final actions = ref.read(modelActionsProvider);

  // Download then auto-load — user sees progress in the home screen
  await actions.loadModel(starter);
});

/// Whether the user has finished (or can skip) first-run onboarding. Existing
/// users who already have a model installed are treated as onboarded.
final onboardingStatusProvider = FutureProvider<bool>((ref) async {
  final settings = ref.read(settingsServiceProvider);
  if (await settings.getOnboardingComplete()) return true;
  final downloaded = await ref.read(modelStorageProvider).downloadedModelIds();
  if (downloaded.isNotEmpty) {
    await settings.setOnboardingComplete(true);
    return true;
  }
  return false;
});

// ─────────────────────────────────────────────────────────────────────────────
// Storage + download
// ─────────────────────────────────────────────────────────────────────────────

final modelStorageProvider = Provider<ModelStorageService>(
  (_) => ModelStorageService(),
);

final modelDownloadProvider = Provider<ModelDownloadService>((ref) {
  final svc = ModelDownloadService(storage: ref.read(modelStorageProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

// ─────────────────────────────────────────────────────────────────────────────
// Download state map  (modelId → DownloadState)
// ─────────────────────────────────────────────────────────────────────────────

final downloadStatesProvider =
    StateNotifierProvider<DownloadStatesNotifier, Map<String, DownloadState>>(
  (ref) => DownloadStatesNotifier(ref),
);

class DownloadStatesNotifier
    extends StateNotifier<Map<String, DownloadState>> {
  DownloadStatesNotifier(this._ref) : super({}) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<MapEntry<String, DownloadState>>? _sub;

  Future<void> _init() async {
    // Seed initial state from disk
    final storage = _ref.read(modelStorageProvider);
    final downloaded = await storage.downloadedModelIds();

    state = {
      for (final id in downloaded) id: DownloadState.downloaded,
    };

    // Subscribe to live download events
    _sub = _ref
        .read(modelDownloadProvider)
        .progressStream
        .listen((entry) {
      state = {...state, entry.key: entry.value};
    });
  }

  DownloadState stateFor(String modelId) =>
      state[modelId] ?? DownloadState.notDownloaded;

  void removeState(String modelId) {
    final next = Map<String, DownloadState>.from(state);
    next.remove(modelId);
    state = next;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active model
// ─────────────────────────────────────────────────────────────────────────────

final activeModelProvider = StateProvider<ModelVariant?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Model actions — download / load / unload
// ─────────────────────────────────────────────────────────────────────────────

final modelActionsProvider = Provider<ModelActions>((ref) => ModelActions(ref));

class ModelActions {
  ModelActions(this._ref);
  final Ref _ref;

  /// Guards against two concurrent loads racing into the native engine
  /// (which unloads-then-loads and can crash if re-entered).
  bool _loading = false;

  /// Download [model] from Hugging Face. No-op if already downloading.
  Future<void> download(ModelVariant model) {
    final svc = _ref.read(modelDownloadProvider);
    return svc.download(model.id, model.downloadUrl);
  }

  void cancelDownload(String modelId) {
    _ref.read(modelDownloadProvider).cancel(modelId);
  }

  /// Download (if needed) then load [model] into the inference engine.
  Future<void> loadModel(ModelVariant model) async {
    if (_loading) {
      DiagLog.log('loadModel id=${model.id} SKIPPED (a load is already running)');
      return;
    }
    _loading = true;
    try {
      await _loadModelImpl(model);
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadModelImpl(ModelVariant model) async {
    final storage = _ref.read(modelStorageProvider);

    // A file merely existing isn't enough — a cancelled/failed download leaves a
    // truncated .gguf that would crash the loader. Require it to be at least
    // ~85% of the expected size to count as complete.
    Future<bool> isComplete() async {
      if (!await storage.isDownloaded(model.id)) return false;
      if (model.fileSizeBytes <= 0) return true; // unknown expected size
      final onDisk = await storage.downloadedSizeBytes(model.id);
      return onDisk >= model.fileSizeBytes * 0.85;
    }

    final isReady = await isComplete();
    DiagLog.log('loadModel id=${model.id} alreadyComplete=$isReady');

    if (!isReady) {
      // download() awaits the full transfer (resuming a partial via Range).
      await download(model);
      if (!await isComplete()) {
        DiagLog.log('loadModel id=${model.id} DOWNLOAD INCOMPLETE');
        // Remove the bad/partial file so a retry starts clean.
        try { await storage.delete(model.id); } catch (_) {}
        _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.error;
        throw Exception('Download did not finish. Check your connection and try again.');
      }
    }

    final path = await storage.modelPath(model.id);
    final sizeBytes = await storage.downloadedSizeBytes(model.id);
    DiagLog.log('loadModel id=${model.id} fileMB=${(sizeBytes / 1e6).toStringAsFixed(1)} '
        'expectedMB=${(model.fileSizeBytes / 1e6).toStringAsFixed(1)}');
    final runner = _ref.read(llamaRunnerProvider);
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.loading;

    try {
      await runner.load(model, path);
      DiagLog.log('loadModel id=${model.id} NATIVE LOAD OK');

      // Multimodal models need a vision projector (mmproj) loaded too.
      if (model.isMultimodal && model.mmprojUrl != null) {
        try {
          final mmprojPath = await storage.mmprojPath(model.id);
          if (!await storage.isMmprojDownloaded(model.id)) {
            await _downloadFile(model.mmprojUrl!, mmprojPath);
          }
          await runner.loadProjector(mmprojPath);
        } catch (_) {
          // Vision projector failed — model still works for text.
        }
      }

      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
      _ref.read(activeModelProvider.notifier).state = model;

      // Persist as the default for next launch
      _ref.read(settingsServiceProvider).setLastModelId(model.id);

      // Signal Siri that a model is ready
      _ref.read(siriServiceProvider).setModelReady(true);
    } catch (e) {
      DiagLog.log('loadModel id=${model.id} LOAD FAILED: $e');
      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.error;
      rethrow;
    }
  }

  /// Downloads a file (e.g. the mmproj projector) directly to [destPath].
  ///
  /// URLs can come from the remote catalogue, so they get the same guardrails
  /// as the main GGUF download: https only, and no host that resolves to a
  /// loopback/private address (SSRF).
  Future<void> _downloadFile(String url, String destPath) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw ArgumentError('Download URL must be https: $url');
    }
    if (!await UrlFetchService.isSafeUrlResolved(uri)) {
      throw ArgumentError('Download URL rejected: $url');
    }
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
    await dio.download(
      url,
      destPath,
      options: Options(receiveTimeout: const Duration(minutes: 30)),
    );
  }

  Future<void> unloadModel() async {
    final runner = _ref.read(llamaRunnerProvider);
    await runner.unload();
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.idle;
    _ref.read(activeModelProvider.notifier).state = null;
    _ref.read(siriServiceProvider).setModelReady(false);
  }

}
