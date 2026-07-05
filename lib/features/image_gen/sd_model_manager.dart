import 'dart:async';
import 'dart:io' hide Platform;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'image_gen_real.dart';
import 'sd_model_catalogue.dart';

enum SDModelState {
  notDownloaded,
  downloading,
  extracting,
  ready,
  loading,
  loaded,
  error
}

class SDModelStatus {
  const SDModelStatus({
    required this.state,
    this.downloadProgress = 0.0,
    this.errorMessage,
    this.loadedModelId,
  });

  final SDModelState state;
  final double downloadProgress;
  final String? errorMessage;
  final String? loadedModelId;

  SDModelStatus copyWith({
    SDModelState? state,
    double? downloadProgress,
    String? errorMessage,
    String? loadedModelId,
  }) =>
      SDModelStatus(
        state: state ?? this.state,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        errorMessage: errorMessage,
        loadedModelId: loadedModelId ?? this.loadedModelId,
      );
}

class SDModelNotifier extends StateNotifier<SDModelStatus> {
  SDModelNotifier(this._gen)
      : super(const SDModelStatus(state: SDModelState.notDownloaded)) {
    _checkExisting();
  }

  final LocalImageGenReal _gen;
  final _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    },
    followRedirects: true,
    maxRedirects: 5,
  ));
  CancelToken? _cancelToken;

  Future<Directory> get _modelsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sd_models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String> _modelPath(String modelId) async {
    final dir = await _modelsDir;
    return '${dir.path}/$modelId';
  }

  Future<void> _checkExisting() async {
    for (final m in kSDModelCatalogue) {
      final path = await _modelPath(m.id);
      if (Directory(path).existsSync()) {
        state = SDModelStatus(state: SDModelState.ready, loadedModelId: m.id);
        return;
      }
    }
  }

  // ── Download ────────────────────────────────────────────────────────────────

  Future<void> download(SDModel model) async {
    if (!Platform.isIOS) return; // Core ML not available on Android
    if (state.state == SDModelState.downloading) return;

    // Catalogue URLs are hardcoded to Hugging Face, but keep the same https
    // guardrail as every other download in case that ever changes.
    final uri = Uri.tryParse(model.downloadUrl);
    if (uri == null || uri.scheme != 'https') {
      state = SDModelStatus(
        state: SDModelState.error,
        loadedModelId: model.id,
        errorMessage: 'Invalid download URL (must be https).',
      );
      return;
    }

    final dir = await _modelsDir;
    final zipPath = '${dir.path}/${model.id}.zip';
    final destPath = await _modelPath(model.id);
    _cancelToken = CancelToken();

    // Immediately show progress for this model
    state = SDModelStatus(
      state: SDModelState.downloading,
      downloadProgress: 0,
      loadedModelId: model.id,
    );

    try {
      await _dio.download(
        model.downloadUrl,
        zipPath,
        cancelToken: _cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = state.copyWith(
              downloadProgress: received / total,
              loadedModelId: model.id,
            );
          }
        },
      );

      state = SDModelStatus(
        state: SDModelState.extracting,
        loadedModelId: model.id,
      );

      // Pure-Dart zip extraction — no shell available on iOS
      await _extractZip(zipPath, destPath);

      // Remove zip after extraction
      try {
        File(zipPath).deleteSync();
      } catch (_) {}

      state = SDModelStatus(state: SDModelState.ready, loadedModelId: model.id);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = const SDModelStatus(state: SDModelState.notDownloaded);
      } else {
        state = SDModelStatus(
          state: SDModelState.error,
          loadedModelId: model.id,
          errorMessage: e.message ?? e.toString(),
        );
      }
    } catch (e) {
      state = SDModelStatus(
        state: SDModelState.error,
        loadedModelId: model.id,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _extractZip(String zipPath, String destPath) async {
    // Run extraction in a separate isolate so the UI thread stays free.
    // Uses InputFileStream (streaming) to avoid loading the whole zip into RAM.
    await Isolate.run(() => _extractZipSync(zipPath, destPath));
  }

  static void _extractZipSync(String zipPath, String destPath) {
    final inputStream = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(inputStream);
      final dest = Directory(destPath);
      if (!dest.existsSync()) dest.createSync(recursive: true);
      for (final file in archive) {
        // Zip-slip guard: entry names come from a remote archive. Reject
        // absolute paths, drive letters, and any '..' traversal segment so
        // an entry can never write outside destPath.
        final name = file.name.replaceAll(r'\', '/');
        if (name.startsWith('/') ||
            name.contains(':') ||
            name.split('/').contains('..')) {
          continue;
        }
        if (file.isSymbolicLink) continue;
        final filePath = '$destPath/$name';
        if (file.isFile) {
          final outFile = File(filePath);
          outFile.createSync(recursive: true);
          final outStream = OutputFileStream(filePath);
          file.writeContent(outStream);
          outStream.close();
        } else {
          Directory(filePath).createSync(recursive: true);
        }
      }
    } finally {
      inputStream.close();
    }
  }

  // ── Load ────────────────────────────────────────────────────────────────────

  Future<void> loadModel(SDModel model) async {
    if (!Platform.isIOS) return; // Core ML not available on Android
    final path = await _modelPath(model.id);
    if (!Directory(path).existsSync()) {
      state = SDModelStatus(
        state: SDModelState.error,
        loadedModelId: model.id,
        errorMessage: 'Model not downloaded',
      );
      return;
    }

    state = SDModelStatus(state: SDModelState.loading, loadedModelId: model.id);
    try {
      // Find the actual .mlmodelc directory inside the extracted folder
      final modelDir = _findModelDir(path) ?? path;
      await _gen.loadModel(modelDir);
      state =
          SDModelStatus(state: SDModelState.loaded, loadedModelId: model.id);
    } catch (e) {
      state = SDModelStatus(
        state: SDModelState.error,
        loadedModelId: model.id,
        errorMessage: e.toString(),
      );
    }
  }

  /// CoreML zips typically nest the model inside a subdirectory.
  /// Walk one level deep to find the directory that contains unet/
  String? _findModelDir(String basePath) {
    try {
      final base = Directory(basePath);
      for (final entry in base.listSync()) {
        if (entry is Directory) {
          final sub = Directory(entry.path);
          final hasUnet = sub.listSync().any((e) => e.path.contains('Unet'));
          if (hasUnet) return entry.path;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<void> deleteModel(SDModel model) async {
    final path = await _modelPath(model.id);
    if (Directory(path).existsSync()) {
      Directory(path).deleteSync(recursive: true);
    }
    if (state.loadedModelId == model.id) {
      state = const SDModelStatus(state: SDModelState.notDownloaded);
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  bool isDownloaded(String modelId) {
    return state.loadedModelId == modelId &&
        (state.state == SDModelState.ready ||
            state.state == SDModelState.loaded);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final _imageGenRealProvider = Provider<LocalImageGenReal>((ref) {
  final svc = LocalImageGenReal();
  ref.onDispose(svc.dispose);
  return svc;
});

final sdModelProvider =
    StateNotifierProvider<SDModelNotifier, SDModelStatus>((ref) {
  return SDModelNotifier(ref.read(_imageGenRealProvider));
});

/// Non-null when a real Core ML model is loaded and ready.
final activeImageGenProvider = Provider<LocalImageGenReal?>((ref) {
  final status = ref.watch(sdModelProvider);
  if (status.state == SDModelState.loaded) {
    return ref.read(_imageGenRealProvider);
  }
  return null;
});
