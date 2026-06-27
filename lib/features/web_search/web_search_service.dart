import 'dart:convert';
import 'package:dio/dio.dart';

/// Fetches a DuckDuckGo Instant Answer for a query.
/// Free, no API key required.
class WebSearchService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Returns a formatted context block ready to prepend to the LLM prompt.
  /// Returns null if the search returns nothing useful.
  Future<String?> search(String query) async {
    try {
      final resp = await _dio.get(
        'https://api.duckduckgo.com/',
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '1',
          'no_redirect': '1',
        },
      );

      if (resp.statusCode != 200) return null;
      final data = resp.data is String
          ? jsonDecode(resp.data as String) as Map<String, dynamic>
          : resp.data as Map<String, dynamic>;

      final lines = <String>[];

      final answer = (data['Answer'] as String?)?.trim() ?? '';
      if (answer.isNotEmpty) lines.add('Answer: $answer');

      final abstract = (data['AbstractText'] as String?)?.trim() ?? '';
      final abstractSrc = (data['AbstractSource'] as String?)?.trim() ?? '';
      if (abstract.isNotEmpty) {
        lines.add('Summary${abstractSrc.isNotEmpty ? " (via $abstractSrc)" : ""}: $abstract');
      }

      final topics = data['RelatedTopics'] as List<dynamic>? ?? [];
      int added = 0;
      for (final t in topics) {
        if (added >= 3) break;
        if (t is Map<String, dynamic>) {
          final text = (t['Text'] as String?)?.trim() ?? '';
          if (text.isNotEmpty && text.length > 20) {
            lines.add('- $text');
            added++;
          }
        }
      }

      if (lines.isEmpty) return null;

      return '[Web search results for "$query"]\n${lines.join('\n')}\n[End of search results]';
    } catch (_) {
      return null;
    }
  }
}
