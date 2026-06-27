import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/theme.dart';

/// Runs HTML/CSS/JS code in a sandboxed full-screen WebView.
class HtmlSandboxScreen extends StatefulWidget {
  const HtmlSandboxScreen({super.key, required this.html});
  final String html;

  static void open(BuildContext context, String html) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HtmlSandboxScreen(html: html),
      ),
    );
  }

  @override
  State<HtmlSandboxScreen> createState() => _HtmlSandboxScreenState();
}

class _HtmlSandboxScreenState extends State<HtmlSandboxScreen> {
  late final WebViewController _ctrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadHtmlString(_wrapHtml(widget.html));
  }

  String _wrapHtml(String html) {
    // If already a full document, use as-is
    if (html.contains('<html') || html.contains('<!DOCTYPE')) return html;
    // Otherwise wrap in a minimal dark-mode document
    return '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { background: #0f1d38; color: #e8edf7; font-family: -apple-system, sans-serif; margin: 16px; }
  a { color: #4e9bff; }
  pre, code { background: #1a2744; padding: 8px; border-radius: 6px; overflow-x: auto; }
</style>
</head>
<body>
$html
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        title: const Text('Live Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy HTML',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.html));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('HTML copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              setState(() => _loading = true);
              _ctrl.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _ctrl),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.accentGreen),
            ),
        ],
      ),
    );
  }
}
