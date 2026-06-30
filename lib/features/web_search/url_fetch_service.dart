import 'dart:io';

/// Fetches a URL's text content and returns it stripped of HTML tags,
/// suitable for pasting into an LLM context window.
class UrlFetchService {
  static final _urlRe = RegExp(
    r'https?://[^\s<>"]+[^\s<>"\.,;:!?\)]',
    caseSensitive: false,
  );

  /// Returns non-null if [text] contains a bare URL that should be fetched.
  static String? extractUrl(String text) {
    final m = _urlRe.firstMatch(text.trim());
    return m?.group(0);
  }

  /// Fetches [url] and returns cleaned plain text (max 8 000 chars).
  /// Returns null on any error.
  Future<String?> fetch(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'PintSizeAi/1.0 (compatible; iOS)');
      req.headers.set('Accept', 'text/html,text/plain');
      final resp = await req.close();
      if (resp.statusCode != 200) return null;

      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
        if (bytes.length > 300 * 1024) break; // stop at 300 KB
      }
      client.close();

      var body = String.fromCharCodes(bytes);
      body = _stripHtml(body);
      body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      if (body.length > 8000) body = '${body.substring(0, 8000)}…';
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    }
  }

  static String _stripHtml(String html) {
    // Remove script, style, head blocks
    var s = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<head[^>]*>.*?</head>', dotAll: true, caseSensitive: false), '');
    // Replace block elements with newlines
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|li|h[1-6]|tr|blockquote)>', caseSensitive: false), '\n');
    // Strip remaining tags
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode common HTML entities
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return s;
  }
}
