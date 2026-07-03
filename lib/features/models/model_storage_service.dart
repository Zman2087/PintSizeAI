import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages where GGUF model files live on disk.
///
/// All models are stored in:
///   <app documents>/models/<model-id>.gguf
///
/// Using the app documents directory (not temp or cache) so models survive
/// both app relaunches and OS cache purges. The user explicitly downloaded
/// them — we should not delete them silently.
class ModelStorageService {
  static const String _modelsDir = 'models';

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _modelsDir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Model ids come from the bundled catalogue, the remote catalogue JSON,
  /// and Hugging Face imports. Neutralise path separators / traversal so an
  /// id can never resolve to a file outside the models directory.
  static String _safeId(String modelId) =>
      modelId.replaceAll(RegExp(r'[/\\]'), '_').replaceAll('..', '_');

  Future<String> modelPath(String modelId) async {
    final dir = await _root();
    return p.join(dir.path, '${_safeId(modelId)}.gguf');
  }

  /// Path to a model's multimodal projector (mmproj) file, if it has one.
  Future<String> mmprojPath(String modelId) async {
    final dir = await _root();
    return p.join(dir.path, '${_safeId(modelId)}.mmproj.gguf');
  }

  Future<bool> isMmprojDownloaded(String modelId) async {
    return File(await mmprojPath(modelId)).existsSync();
  }

  Future<bool> isDownloaded(String modelId) async {
    final path = await modelPath(modelId);
    return File(path).existsSync();
  }

  Future<int> downloadedSizeBytes(String modelId) async {
    final path = await modelPath(modelId);
    final file = File(path);
    if (!file.existsSync()) return 0;
    return file.lengthSync();
  }

  Future<void> delete(String modelId) async {
    final path = await modelPath(modelId);
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  /// Returns the total bytes used by all downloaded models.
  Future<int> totalUsedBytes() async {
    final dir = await _root();
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        total += entity.lengthSync();
      }
    }
    return total;
  }

  /// Returns all model IDs that are fully downloaded.
  Future<List<String>> downloadedModelIds() async {
    final dir = await _root();
    final ids = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        final name = p.basenameWithoutExtension(entity.path);
        ids.add(name);
      }
    }
    return ids;
  }
}
