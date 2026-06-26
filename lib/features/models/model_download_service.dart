import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'model_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Download state
// ─────────────────────────────────────────────────────────────────────────────

enum DownloadStatus { notDownloaded, downloading, downloaded, error }

class DownloadState {
  const DownloadState({
    required this.status,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final DownloadStatus status;
  final double progress; // 0.0 – 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  static const DownloadState notDownloaded = DownloadState(status: DownloadStatus.notDownloaded);
  static const DownloadState downloaded = DownloadState(status: DownloadStatus.downloaded, progress: 1.0);

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? error,
  }) => DownloadState(
    status: status ?? this.status,
    progress: progress ?? this.progress,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: error ?? this.error,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Manages GGUF downloads with progress reporting and cancel support.
///
/// Downloads are written directly to the final file path (no .tmp staging)
/// because Dio supports resume via the Range header. A partial file is treated
/// as an incomplete download until [DownloadStatus.downloaded] is confirmed.
///
/// Callers listen to [progressStream] for live progress events keyed by modelId.
class ModelDownloadService {
  ModelDownloadService({ModelStorageService? storage})
      : _storage = storage ?? ModelStorageService();

  final ModelStorageService _storage;
  final Dio _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(minutes: 30),
    connectTimeout: const Duration(seconds: 15),
  ));

  final _progress = StreamController<MapEntry<String, DownloadState>>.broadcast();
  final Map<String, CancelToken> _tokens = {};

  /// Stream of (modelId → DownloadState) events.
  Stream<MapEntry<String, DownloadState>> get progressStream => _progress.stream;

  // ── Download ────────────────────────────────────────────────────────────────

  Future<void> download(String modelId, String url) async {
    if (_tokens.containsKey(modelId)) return; // already in flight

    final path = await _storage.modelPath(modelId);
    final token = CancelToken();
    _tokens[modelId] = token;

    _emit(modelId, const DownloadState(status: DownloadStatus.downloading));

    try {
      // Determine existing bytes for resume support
      final existingFile = File(path);
      final existingBytes = existingFile.existsSync() ? existingFile.lengthSync() : 0;

      await _dio.download(
        url,
        path,
        cancelToken: token,
        deleteOnError: false, // keep partial file for resume
        options: Options(
          headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
          responseType: ResponseType.stream,
        ),
        onReceiveProgress: (received, total) {
          final actualTotal = total < 0 ? 0 : total + existingBytes;
          final actualReceived = received + existingBytes;
          _emit(modelId, DownloadState(
            status: DownloadStatus.downloading,
            receivedBytes: actualReceived,
            totalBytes: actualTotal,
            progress: actualTotal > 0 ? (actualReceived / actualTotal).clamp(0.0, 1.0) : 0,
          ));
        },
      );

      _tokens.remove(modelId);
      _emit(modelId, DownloadState.downloaded);
    } on DioException catch (e) {
      _tokens.remove(modelId);
      if (e.type == DioExceptionType.cancel) {
        _emit(modelId, DownloadState.notDownloaded);
      } else {
        _emit(modelId, DownloadState(
          status: DownloadStatus.error,
          error: _friendlyError(e),
        ));
      }
    } catch (e) {
      _tokens.remove(modelId);
      _emit(modelId, DownloadState(
        status: DownloadStatus.error,
        error: e.toString(),
      ));
    }
  }

  // ── Cancel ──────────────────────────────────────────────────────────────────

  void cancel(String modelId) {
    _tokens[modelId]?.cancel();
    _tokens.remove(modelId);
  }

  void cancelAll() {
    for (final t in _tokens.values) t.cancel();
    _tokens.clear();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _emit(String modelId, DownloadState state) {
    if (!_progress.isClosed) {
      _progress.add(MapEntry(modelId, state));
    }
  }

  String _friendlyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.badResponse:
        return 'Server error (${e.response?.statusCode}). Try again later.';
      default:
        return 'Download failed: ${e.message}';
    }
  }

  void dispose() {
    cancelAll();
    _progress.close();
  }
}
