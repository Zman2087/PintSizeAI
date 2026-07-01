import 'package:dio/dio.dart';
import '../device_recommender/model_catalogue.dart';

/// A GGUF model repository on Hugging Face.
class HFRepo {
  const HFRepo({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.lastModified,
    required this.tags,
  });

  final String id; // e.g. "bartowski/Llama-3.2-3B-Instruct-GGUF"
  final int downloads;
  final int likes;
  final String lastModified; // ISO date
  final List<String> tags;

  String get owner => id.contains('/') ? id.split('/').first : '';
  String get name => id.contains('/') ? id.split('/').last : id;

  /// Friendly model name (strip the "-GGUF" suffix and owner).
  String get displayName =>
      name.replaceAll(RegExp(r'[-_]?GGUF$', caseSensitive: false), '');
}

/// A single GGUF file (quant) inside a repo.
class HFFile {
  const HFFile({required this.path, required this.sizeBytes});
  final String path; // e.g. "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
  final int sizeBytes;

  /// The quant label parsed from the filename, e.g. "Q4_K_M".
  String get quantLabel {
    final m = RegExp(
      r'(IQ\d[_A-Z0-9]*|Q\d[_A-Z0-9]*|F16|F32|BF16)',
      caseSensitive: false,
    ).firstMatch(path);
    return m?.group(0)?.toUpperCase() ?? 'GGUF';
  }
}

/// Queries Hugging Face's public API to discover and download GGUF models.
/// No API key required.
class HuggingFaceService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    headers: {
      'User-Agent':
          'PintSizeAi/1.0 (https://github.com/Zman2087/PintSizeAI)',
    },
  ));

  /// Lists popular GGUF text-generation models, optionally filtered by [query].
  Future<List<HFRepo>> search({String query = '', int limit = 30}) async {
    try {
      final resp = await _dio.get(
        'https://huggingface.co/api/models',
        queryParameters: {
          'filter': 'gguf',
          'pipeline_tag': 'text-generation',
          'sort': 'downloads',
          'direction': '-1',
          'limit': limit,
          if (query.trim().isNotEmpty) 'search': query.trim(),
        },
      );
      final list = (resp.data as List?) ?? const [];
      return list.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return HFRepo(
          id: m['id'] as String? ?? m['modelId'] as String? ?? '',
          downloads: (m['downloads'] as num?)?.toInt() ?? 0,
          likes: (m['likes'] as num?)?.toInt() ?? 0,
          lastModified: (m['lastModified'] as String?) ?? '',
          tags: (m['tags'] as List?)?.map((t) => '$t').toList() ?? const [],
        );
      }).where((r) => r.id.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lists the single-file GGUF quants available in [repoId], smallest first.
  /// Multi-part GGUFs (…-of-…) are skipped for simplicity.
  Future<List<HFFile>> ggufFiles(String repoId) async {
    try {
      final resp = await _dio.get(
        'https://huggingface.co/api/models/$repoId/tree/main',
        queryParameters: {'recursive': 'true'},
      );
      final list = (resp.data as List?) ?? const [];
      final files = <HFFile>[];
      for (final e in list) {
        final m = (e as Map).cast<String, dynamic>();
        final path = m['path'] as String? ?? '';
        final lower = path.toLowerCase();
        if (!lower.endsWith('.gguf')) continue;
        // Skip multi-part shards (loader needs a single file).
        if (RegExp(r'-of-\d+', caseSensitive: false).hasMatch(path)) continue;
        // Skip companion files that are NOT loadable language models — these
        // are the cause of "Could not open model file" (e.g. vision projectors).
        if (_isNonModelFile(lower)) continue;
        final size = (m['size'] as num?)?.toInt() ??
            (m['lfs'] is Map ? ((m['lfs']['size'] as num?)?.toInt() ?? 0) : 0);
        files.add(HFFile(path: path, sizeBytes: size));
      }
      files.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// True for GGUF files that are NOT standalone language models (vision
  /// projectors, CLIP encoders, etc.) — these fail to load as a model.
  static bool _isNonModelFile(String lowerPath) {
    const markers = ['mmproj', 'clip', 'projector', 'vision', 'mm-proj'];
    return markers.any(lowerPath.contains);
  }

  /// Builds a [ModelVariant] for a chosen repo + file so it can flow through the
  /// normal download/load pipeline.
  static ModelVariant toModelVariant(HFRepo repo, HFFile file) {
    final params = _parseParams(repo.name);
    final quant = _parseQuant(file.quantLabel);
    final ramBytes = (file.sizeBytes * 1.18).round();
    final url =
        'https://huggingface.co/${repo.id}/resolve/main/${file.path}';
    // Stable id derived from repo + file so re-adds dedupe and persist works.
    final id = 'hf_${repo.id}_${file.path}'
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .toLowerCase();

    return ModelVariant(
      id: id,
      displayName: repo.displayName,
      family: _inferFamily(repo.id),
      parametersBillions: params,
      quant: quant,
      fileSizeBytes: file.sizeBytes,
      ramRequiredBytes: ramBytes,
      contextLength: 4096,
      downloadUrl: url,
      strengths: const ['Community GGUF model'],
      creator: repo.owner,
      description:
          'Imported from Hugging Face (${repo.id}). Quant: ${file.quantLabel}. '
          '${repo.downloads} downloads · ${repo.likes} likes.',
      minRamGbRecommended: (ramBytes / 1e9).ceil().clamp(2, 24),
      huggingFaceUrl: 'https://huggingface.co/${repo.id}',
    );
  }

  static double _parseParams(String name) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*[bB]\b').firstMatch(name);
    if (m != null) return double.tryParse(m.group(1)!) ?? 0;
    return 0;
  }

  static Quant _parseQuant(String label) {
    final l = label.toUpperCase();
    if (l.contains('Q2')) return Quant.q2k;
    if (l.contains('Q3')) return Quant.q3km;
    if (l.contains('Q4')) return Quant.q4km;
    if (l.contains('Q5')) return Quant.q5km;
    if (l.contains('Q6') || l.contains('Q8')) return Quant.q8;
    if (l.contains('F16') || l.contains('BF16') || l.contains('F32')) {
      return Quant.fp16;
    }
    return Quant.q4km;
  }

  static ModelFamily _inferFamily(String id) {
    final l = id.toLowerCase();
    if (l.contains('llama')) return ModelFamily.llama;
    if (l.contains('qwen')) return ModelFamily.qwen;
    if (l.contains('gemma')) return ModelFamily.gemma;
    if (l.contains('phi')) return ModelFamily.phi;
    if (l.contains('mistral') || l.contains('mixtral')) {
      return ModelFamily.mistral;
    }
    if (l.contains('deepseek')) return ModelFamily.deepseek;
    if (l.contains('smol')) return ModelFamily.smollm;
    return ModelFamily.llama;
  }
}
