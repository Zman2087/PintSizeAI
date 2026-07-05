import 'dart:convert';
import 'package:dio/dio.dart';

/// Fetches web context for a query. Tries DuckDuckGo's Instant Answer API
/// first (clean, structured), then falls back to scraping the DuckDuckGo
/// HTML results page so general/conversational queries also get results.
/// Free, no API key required.
class WebSearchService {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    },
  ));

  /// Returns a formatted context block ready to prepend to the LLM prompt.
  /// Returns null if nothing useful was found.
  Future<String?> search(String query) async {
    final instant = await _instantAnswer(query);
    if (instant != null) return instant;
    return _htmlResults(query);
  }

  // ── DuckDuckGo Instant Answer API ──────────────────────────────────────────

  Future<String?> _instantAnswer(String query) async {
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
        lines.add(
            'Summary${abstractSrc.isNotEmpty ? " (via $abstractSrc)" : ""}: $abstract');
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

  // ── DuckDuckGo HTML results fallback ───────────────────────────────────────

  Future<String?> _htmlResults(String query) async {
    try {
      // Stream the body and stop at 500 KB so an oversized (or hostile)
      // response can't balloon memory — only the first snippets matter.
      final resp = await _dio.get<ResponseBody>(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
        options: Options(responseType: ResponseType.stream),
      );
      if (resp.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in resp.data!.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 500 * 1024) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);

      // Each result snippet sits in <a class="result__snippet">…</a>
      final snippetRe = RegExp(
        r'class="result__snippet"[^>]*>(.*?)</a>',
        dotAll: true,
      );
      final titleRe = RegExp(
        r'class="result__a"[^>]*>(.*?)</a>',
        dotAll: true,
      );

      final titles = titleRe
          .allMatches(html)
          .map((m) => _clean(m.group(1) ?? ''))
          .where((s) => s.isNotEmpty)
          .toList();
      final snippets = snippetRe
          .allMatches(html)
          .map((m) => _clean(m.group(1) ?? ''))
          .where((s) => s.isNotEmpty)
          .toList();

      if (snippets.isEmpty && titles.isEmpty) return null;

      final lines = <String>[];
      final count = snippets.length;
      for (var i = 0; i < count && i < 4; i++) {
        final title = i < titles.length ? titles[i] : '';
        final snip = snippets[i];
        lines.add(title.isNotEmpty ? '- $title: $snip' : '- $snip');
      }

      if (lines.isEmpty) return null;
      return '[Web search results for "$query"]\n${lines.join('\n')}\n[End of search results]';
    } catch (_) {
      return null;
    }
  }

  static String _clean(String html) {
    var s = html.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
