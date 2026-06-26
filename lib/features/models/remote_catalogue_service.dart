import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../device_recommender/model_catalogue.dart';

/// URL of the remote catalogue JSON, served from the app's GitHub repo.
/// Update this URL if the repo is renamed or the file moves.
const _kCatalogueUrl =
    'https://raw.githubusercontent.com/Zman2087/PintSizeAI/main/catalogue/models.json';

const _kCacheKey = 'remote_catalogue_json';
const _kCacheTimestampKey = 'remote_catalogue_fetched_at';
const _kCacheTtlHours = 12;

/// Fetches the remote model catalogue and merges it with the bundled one.
///
/// Strategy:
///   1. Serve cached JSON immediately (so the app starts fast).
///   2. In the background, try to refresh from the network.
///   3. If the network fetch fails, the cached / bundled catalogue is used.
///   4. Remote entries take precedence over bundled entries with the same id.
class RemoteCatalogueService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the merged catalogue. First resolves from cache, then kicks off
  /// a background refresh. Callers watching the Riverpod provider will be
  /// notified when the fresh data arrives.
  Future<List<ModelVariant>> loadMerged() async {
    final cached = await _loadCached();
    _refreshInBackground(); // fire-and-forget; provider rebuilds on completion
    return _merge(cached);
  }

  /// Forces an immediate network fetch. Useful for a "Refresh" button.
  Future<List<ModelVariant>> forceRefresh() async {
    final fresh = await _fetch();
    if (fresh != null) await _saveCache(fresh);
    return _merge(fresh);
  }

  // ── Network ───────────────────────────────────────────────────────────────

  Future<void> _refreshInBackground() async {
    try {
      final cacheAge = await _cacheAgeHours();
      if (cacheAge < _kCacheTtlHours) return; // still fresh

      final fresh = await _fetch();
      if (fresh != null) await _saveCache(fresh);
    } catch (_) {
      // Silent — network errors are non-fatal
    }
  }

  Future<List<Map<String, dynamic>>?> _fetch() async {
    try {
      final res = await _dio.get<String>(_kCatalogueUrl);
      if (res.statusCode != 200 || res.data == null) return null;
      final body = jsonDecode(res.data!) as Map<String, dynamic>;
      final models = body['models'] as List?;
      if (models == null) return null;
      return models.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw == null) return null;
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(List<Map<String, dynamic>> models) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode(models));
      await prefs.setInt(
          _kCacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<double> _cacheAgeHours() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_kCacheTimestampKey);
      if (ts == null) return double.infinity;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      return age / (1000 * 60 * 60);
    } catch (_) {
      return double.infinity;
    }
  }

  // ── Merge ─────────────────────────────────────────────────────────────────

  /// Merges remote entries with the bundled catalogue.
  /// Remote entries override bundled entries that share the same [id].
  /// New remote entries (unknown ids) are appended.
  List<ModelVariant> _merge(List<Map<String, dynamic>>? remote) {
    if (remote == null) return kModelCatalogue;

    final result = <String, ModelVariant>{
      for (final m in kModelCatalogue) m.id: m,
    };

    for (final entry in remote) {
      try {
        final model = ModelVariant.fromJson(entry);
        result[model.id] = model; // remote wins on conflict
      } catch (_) {
        // Skip malformed entries
      }
    }

    return result.values.toList();
  }
}
