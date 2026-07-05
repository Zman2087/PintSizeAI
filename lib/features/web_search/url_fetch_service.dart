import 'dart:async';
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

  /// Like [isSafeUrl], but also resolves the hostname so a DNS name pointing
  /// at a loopback/link-local/private address is rejected too — [isSafeUrl]
  /// alone only catches literal IPs.
  static Future<bool> isSafeUrlResolved(Uri uri) async {
    if (!isSafeUrl(uri)) return false;
    if (InternetAddress.tryParse(uri.host) != null)
      return true; // literal, already vetted
    try {
      final addrs = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 5));
      if (addrs.isEmpty) return false;
      for (final a in addrs) {
        if (a.isLoopback || a.isLinkLocal || _isPrivateIp(a)) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches [url] and returns cleaned plain text (max 8 000 chars).
  /// Returns null on any error.
  Future<String?> fetch(String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null) return null;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      // Follow redirects manually so every hop — not just the first URL —
      // is vetted (incl. DNS resolution) before we connect to it.
      HttpClientResponse? resp;
      for (var hop = 0; hop < 5; hop++) {
        if (!await isSafeUrlResolved(uri!)) return null;
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        req.headers.set('User-Agent', 'PintSizeAi/1.0 (compatible; iOS)');
        req.headers.set('Accept', 'text/html,text/plain');
        final r = await req.close().timeout(const Duration(seconds: 15));
        if (r.isRedirect) {
          final loc = r.headers.value(HttpHeaders.locationHeader);
          if (loc == null) return null;
          unawaited(r.drain<void>().catchError((_) {}));
          uri = uri.resolve(loc);
          continue;
        }
        resp = r;
        break;
      }
      if (resp == null || resp.statusCode != 200) return null;

      final bytes = <int>[];
      // Per-chunk timeout defeats slow-loris servers that trickle bytes to
      // pin the connection open; the byte cap bounds memory.
      await for (final chunk in resp.timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) => sink.close(),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 300 * 1024) break; // stop at 300 KB
      }

      var body = String.fromCharCodes(bytes);
      body = _stripHtml(body);
      body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      if (body.length > 8000) body = '${body.substring(0, 8000)}…';
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _stripHtml(String html) {
    // Remove script, style, head blocks
    var s = html
        .replaceAll(
            RegExp(r'<script[^>]*>.*?</script>',
                dotAll: true, caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'<style[^>]*>.*?</style>',
                dotAll: true, caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'<head[^>]*>.*?</head>',
                dotAll: true, caseSensitive: false),
            '');
    // Replace block elements with newlines
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(r'</(p|div|li|h[1-6]|tr|blockquote)>', caseSensitive: false),
        '\n');
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
