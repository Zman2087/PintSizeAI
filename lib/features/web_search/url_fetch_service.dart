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

  /// True if [uri] is safe to fetch: http(s) only, and not a loopback,
  /// link-local, or private-network address (SSRF guard — keeps pasted or
  /// model-suggested URLs from probing the local device or LAN).
  static bool isSafeUrl(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return false;
    }
    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.isLoopback || ip.isLinkLocal || _isPrivateIp(ip)) return false;
    }
    return true;
  }

  static bool _isPrivateIp(InternetAddress ip) {
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 0 || // 0.0.0.0/8
          b[0] == 10 || // 10/8
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) || // 100.64/10 (CGNAT)
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || // 172.16/12
          (b[0] == 192 && b[1] == 168); // 192.168/16
    }
    return (b[0] & 0xfe) == 0xfc; // IPv6 unique-local fc00::/7
  }

  /// Fetches [url] and returns cleaned plain text (max 8 000 chars).
  /// Returns null on any error.
  Future<String?> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !isSafeUrl(uri)) return null;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'PintSizeAi/1.0 (compatible; iOS)');
      req.headers.set('Accept', 'text/html,text/plain');
      final resp = await req.close();
      // Re-check every redirect hop — a public URL must not be able to
      // bounce the fetch onto localhost or a private address.
      for (final r in resp.redirects) {
        if (!isSafeUrl(uri.resolveUri(r.location))) {
          client.close(force: true);
          return null;
        }
      }
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
