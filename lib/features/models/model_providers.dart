import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../device_recommender/model_catalogue.dart';
import '../llm/llama_runner.dart';
import '../llm/llm_providers.dart';
import '../settings/settings_providers.dart';
import '../siri/siri_service.dart';
import 'model_download_service.dart';
import 'model_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// First-launch auto-download
// ─────────────────────────────────────────────────────────────────────────────

/// Triggers once on first launch. If no model is on disk, silently
/// downloads kStarterModelId (SmolLM2 135M, ~75 MB) and auto-loads it.
///
/// The download progress is visible in [downloadStatesProvider], so the
/// home screen welcome view shows the progress bar automatically.
final firstLaunchSetupProvider = FutureProvider<void>((ref) async {
  final storage = ref.read(modelStorageProvider);
  final downloaded = await storage.downloadedModelIds();
  if (downloaded.isNotEmpty) return; // already has a model

  final starter = kModelCatalogue.firstWhere((m) => m.id == kStarterModelId);
  final actions = ref.read(modelActionsProvider);

  // Download then auto-load — user sees progress in the home screen
  await actions.loadModel(starter);
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
    final storage = _ref.read(modelStorageProvider);
    final isReady = await storage.isDownloaded(model.id);

    if (!isReady) {
      await download(model);
      // Wait until downloaded
      await _waitForDownload(model.id);
    }

    final path = await storage.modelPath(model.id);
    final runner = _ref.read(llamaRunnerProvider);
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.loading;

    try {
      await runner.load(model, path);
      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.ready;
      _ref.read(activeModelProvider.notifier).state = model;

      // Persist as the default for next launch
      _ref.read(settingsServiceProvider).setLastModelId(model.id);

      // Signal Siri that a model is ready
      _ref.read(siriServiceProvider).setModelReady(true);
    } catch (e) {
      _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.error;
      rethrow;
    }
  }

  Future<void> unloadModel() async {
    final runner = _ref.read(llamaRunnerProvider);
    await runner.unload();
    _ref.read(llamaStatusProvider.notifier).state = LlamaStatus.idle;
    _ref.read(activeModelProvider.notifier).state = null;
    _ref.read(siriServiceProvider).setModelReady(false);
  }

  Future<void> _waitForDownload(String modelId) async {
    final completer = Completer<void>();
    final sub = _ref.read(modelDownloadProvider).progressStream.listen(
      (entry) {
        if (entry.key == modelId) {
          if (entry.value.status == DownloadStatus.downloaded) {
            if (!completer.isCompleted) completer.complete();
          } else if (entry.value.status == DownloadStatus.error) {
            if (!completer.isCompleted) {
              completer.completeError(entry.value.error ?? 'Download failed');
            }
          }
        }
      },
    );
    try {
      await completer.future;
    } finally {
      sub.cancel();
    }
  }
}
