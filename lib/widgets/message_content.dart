import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../screens/html_sandbox_screen.dart';
import '../theme/theme.dart';
import 'stock_chart_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MessageContent
// ─────────────────────────────────────────────────────────────────────────────

/// Renders an AI message with full markdown, code blocks, tables, and LaTeX.
class MessageContent extends StatelessWidget {
  const MessageContent(this.text, {super.key, this.isStreaming = false});

  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return isStreaming ? const _TypingIndicator() : const SizedBox.shrink();
    }

    // Live stock card embedded in the message text.
    final start = text.indexOf(StockChartCard.startMarker);
    final end = text.indexOf(StockChartCard.endMarker);
    if (start >= 0 && end > start) {
      final before = text.substring(0, start).trim();
      final json =
          text.substring(start + StockChartCard.startMarker.length, end);
      final after =
          text.substring(end + StockChartCard.endMarker.length).trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (before.isNotEmpty)
            _MixedContent(text: before, isStreaming: false),
          StockChartCard(json: json),
          if (after.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MixedContent(text: after, isStreaming: isStreaming),
          ],
        ],
      );
    }

    // Pre-process: split out $...$ and $$...$$ for math rendering
    return _MixedContent(text: text, isStreaming: isStreaming);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mixed content: markdown + inline/block LaTeX
// ─────────────────────────────────────────────────────────────────────────────

class _MixedContent extends StatelessWidget {
  const _MixedContent({required this.text, required this.isStreaming});
  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final segments = _splitMath(text);
    if (segments.length == 1 && !segments.first.isMath) {
      return _MarkdownBlock(
          text: segments.first.content, isStreaming: isStreaming);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.isMath) {
          return _MathBlock(tex: seg.content.trim(), isDisplay: seg.isDisplay);
        }
        return _MarkdownBlock(
            text: seg.content,
            isStreaming: isStreaming && seg == segments.last);
      }).toList(),
    );
  }

  // Split text into markdown and math segments
  static List<_Segment> _splitMath(String src) {
    final result = <_Segment>[];
    // Match $$...$$ (block) and $...$ (inline)
    final re = RegExp(r'\$\$(.+?)\$\$|\$([^\n\$]+?)\$', dotAll: true);
    int pos = 0;
    for (final m in re.allMatches(src)) {
      if (m.start > pos) {
        result.add(_Segment(src.substring(pos, m.start), false, false));
      }
      final isDisplay = m.group(1) != null;
      result.add(
          _Segment(isDisplay ? m.group(1)! : m.group(2)!, true, isDisplay));
      pos = m.end;
    }
    if (pos < src.length) {
      result.add(_Segment(src.substring(pos), false, false));
    }
    return result.isEmpty ? [_Segment(src, false, false)] : result;
  }
}

class _Segment {
  const _Segment(this.content, this.isMath, this.isDisplay);
  final String content;
  final bool isMath;
  final bool isDisplay;
}

// ─────────────────────────────────────────────────────────────────────────────
// Markdown block
// ─────────────────────────────────────────────────────────────────────────────

class _MarkdownBlock extends StatelessWidget {
  const _MarkdownBlock({required this.text, this.isStreaming = false});
  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return isStreaming ? const _TypingIndicator() : const SizedBox.shrink();
    }
    return MarkdownBody(
      data: text,
      styleSheet: _sheet(),
      builders: {'code': _CodeBlockBuilder()},
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      onTapLink: (_, href, __) {},
      shrinkWrap: true,
      softLineBreak: true,
    );
  }

  MarkdownStyleSheet _sheet() => MarkdownStyleSheet(
        p: AppTypography.messageBody,
        strong: AppTypography.messageBody.copyWith(fontWeight: FontWeight.w700),
        em: AppTypography.messageBody.copyWith(fontStyle: FontStyle.italic),
        h1: AppTypography.messageBody
            .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        h2: AppTypography.messageBody
            .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        h3: AppTypography.messageBody
            .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        listBullet: AppTypography.messageBody,
        blockquote:
            AppTypography.messageBody.copyWith(color: AppColors.textMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: AppColors.borderDefault, width: 3)),
        ),
        code: AppTypography.messageBody.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          color: const Color(0xFF7DD3FC),
          backgroundColor: const Color(0xFF0f2940),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF0D1B2E),
          borderRadius: BorderRadius.circular(10),
        ),
        // Table styling
        tableHead: AppTypography.messageBody.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        tableBody: AppTypography.messageBody,
        tableBorder: TableBorder.all(
          color: AppColors.borderDefault,
          width: 1,
          borderRadius: BorderRadius.circular(4),
        ),
        tableHeadAlign: TextAlign.left,
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        tableColumnWidth: const FlexColumnWidth(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Math block (inline or display)
// ─────────────────────────────────────────────────────────────────────────────

class _MathBlock extends StatelessWidget {
  const _MathBlock({required this.tex, required this.isDisplay});
  final String tex;
  final bool isDisplay;

  @override
  Widget build(BuildContext context) {
    final widget = Math.tex(
      tex,
      textStyle: AppTypography.messageBody,
      onErrorFallback: (e) => SelectableText(
        tex,
        style: AppTypography.messageBody
            .copyWith(color: AppColors.textMuted, fontFamily: 'monospace'),
      ),
    );
    if (isDisplay) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(child: widget),
      );
    }
    return widget;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom code block builder
// ─────────────────────────────────────────────────────────────────────────────

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    dynamic element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent as String? ?? '';
    final lang = (element.attributes['class'] as String? ?? '')
        .replaceFirst('language-', '');
    return _CodeBlock(code: code.trimRight(), language: lang);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CodeBlock widget
// ─────────────────────────────────────────────────────────────────────────────

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, required this.language});
  final String code;
  final String language;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  bool get _isWebRunnable => ['html', 'htm', 'css', 'javascript', 'js', 'svg']
      .contains(widget.language.toLowerCase());

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language.isEmpty ? 'code' : widget.language;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0F2244),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(
                  lang,
                  style: const TextStyle(
                    color: Color(0xFF7DD3FC),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (_isWebRunnable)
                  _HeaderBtn(
                    label: 'Run',
                    icon: Icons.play_circle_outline,
                    color: const Color(0xFF22C55E),
                    onTap: () => HtmlSandboxScreen.open(context, widget.code),
                  ),
                const SizedBox(width: 8),
                _HeaderBtn(
                  label: _copied ? 'Copied' : 'Copy',
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  color: AppColors.textMuted,
                  onTap: _copy,
                ),
              ],
            ),
          ),
          // Code body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFCDD9E5),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontFamily: 'monospace')),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing indicator
// ─────────────────────────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: Text('▍', style: AppTypography.messageBody),
      );
}
