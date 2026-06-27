import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../screens/html_sandbox_screen.dart';
import '../theme/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MessageContent
// ─────────────────────────────────────────────────────────────────────────────

/// Renders an AI message with full markdown support and custom code blocks
/// (syntax highlighted, copyable, and runnable for HTML).
class MessageContent extends StatelessWidget {
  const MessageContent(this.text, {super.key, this.isStreaming = false});

  final String text;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return isStreaming
          ? const _TypingIndicator()
          : const SizedBox.shrink();
    }

    return MarkdownBody(
      data: text,
      styleSheet: _markdownStyle(),
      builders: {'code': _CodeBlockBuilder()},
      onTapLink: (_, href, __) {
        // links are handled by the parent if needed
      },
      shrinkWrap: true,
      softLineBreak: true,
    );
  }

  MarkdownStyleSheet _markdownStyle() => MarkdownStyleSheet(
        p: AppTypography.messageBody,
        strong: AppTypography.messageBody.copyWith(fontWeight: FontWeight.w700),
        em: AppTypography.messageBody
            .copyWith(fontStyle: FontStyle.italic),
        h1: AppTypography.messageBody.copyWith(
            fontSize: 20, fontWeight: FontWeight.w700),
        h2: AppTypography.messageBody.copyWith(
            fontSize: 17, fontWeight: FontWeight.w700),
        h3: AppTypography.messageBody.copyWith(
            fontSize: 15, fontWeight: FontWeight.w600),
        listBullet: AppTypography.messageBody,
        blockquote: AppTypography.messageBody.copyWith(
            color: AppColors.textMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: AppColors.borderDefault, width: 3),
          ),
        ),
        // Code inline
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
      );
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

  bool get _isWebRunnable =>
      ['html', 'htm', 'css', 'javascript', 'js', 'svg'].contains(
          widget.language.toLowerCase());

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
          // Header bar: language label + buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0F2244),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Text(
                  lang.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (_isWebRunnable)
                  _HeaderBtn(
                    icon: Icons.play_circle_outline,
                    label: 'Run',
                    color: AppColors.accentGreen,
                    onTap: () => HtmlSandboxScreen.open(context, widget.code),
                  ),
                const SizedBox(width: 8),
                _HeaderBtn(
                  icon: _copied ? Icons.check : Icons.copy_outlined,
                  label: _copied ? 'Copied' : 'Copy',
                  color: _copied ? AppColors.accentGreen : const Color(0xFF94A3B8),
                  onTap: _copy,
                ),
              ],
            ),
          ),
          // Code content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFE2E8F0),
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
  const _HeaderBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
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
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Text('▍', style: AppTypography.messageBody),
    );
  }
}
