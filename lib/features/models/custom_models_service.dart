import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../device_recommender/model_catalogue.dart';
import 'huggingface_service.dart';

/// Persists user-added models (imported from Hugging Face) so they survive
/// restarts and appear in the model picker alongside the built-in catalogue.
class CustomModelsService {
  static const _fileName = 'custom_models.json';

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  Future<List<ModelVariant>> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final raw = await f.readAsString();
      final list = (jsonDecode(raw) as List?) ?? const [];
      return list
          .map((e) => ModelVariant.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ModelVariant> models) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(models.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }
}

/// Holds the list of user-imported models.
class CustomModelsNotifier extends StateNotifier<List<ModelVariant>> {
  CustomModelsNotifier(this._service) : super(const []) {
    _service.load().then((m) => state = m);
  }

  final CustomModelsService _service;

  Future<void> add(ModelVariant model) async {
    if (state.any((m) => m.id == model.id)) return;
    state = [model, ...state];
    await _service.save(state);
  }

  Future<void> remove(String id) async {
    state = state.where((m) => m.id != id).toList();
    await _service.save(state);
  }
}

final customModelsServiceProvider =
    Provider<CustomModelsService>((_) => CustomModelsService());

final customModelsProvider =
    StateNotifierProvider<CustomModelsNotifier, List<ModelVariant>>((ref) {
  return CustomModelsNotifier(ref.read(customModelsServiceProvider));
});

final huggingFaceServiceProvider = Provider((ref) => HuggingFaceService());
