import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import '../features/attachments/attachment.dart';
import '../theme/theme.dart';
import '../widgets/message_content.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ModelIcon
// ─────────────────────────────────────────────────────────────────────────────

/// The coloured square icon used on each model in the picker and in the nav.
///
/// Each model family gets a distinct background that maps to its origin —
/// white for Llama/Meta (clean, neutral), blue for Phi (Microsoft brand),
/// green for Gemma (Google brand), purple for Qwen/Mistral (open-source).
class ModelIcon extends StatelessWidget {
  const ModelIcon({
    super.key,
    required this.color,
    required this.icon,
    this.size = 36,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconColor = color == AppColors.modelWhite
        ? AppColors.surfaceSidebar
        : AppColors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.icon,
        border: color == AppColors.modelSurface
            ? Border.all(color: AppColors.borderDefault)
            : null,
      ),
      child: Icon(icon, color: iconColor, size: size * 0.50),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OnDeviceChip
// ─────────────────────────────────────────────────────────────────────────────

/// The "Running on-device · no internet used" indicator shown below the nav.
/// The pulsing green dot is the single branded moment on the chat screen.
class OnDeviceChip extends StatefulWidget {
  const OnDeviceChip({super.key, this.label = 'Running on-device · no internet used'});
  final String label;

  @override
  State<OnDeviceChip> createState() => _OnDeviceChipState();
}

class _OnDeviceChipState extends State<OnDeviceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _opacity,
            builder: (_, __) => Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accentGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.label,
              style: AppTypography.badge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UserMessage
// ─────────────────────────────────────────────────────────────────────────────

/// User message bubble. Right-aligned, surfaceOverlay fill, flattened tail.
class UserMessage extends StatelessWidget {
  const UserMessage({
    super.key,
    required this.text,
    this.attachments = const [],
  });
  final String text;
  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment thumbnails above the bubble
            if (attachments.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: attachments.map((a) => AttachmentThumbnail(a)).toList(),
              ),
              const SizedBox(height: 6),
            ],
            if (text.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: AppRadius.userBubble,
                ),
                child: Text(text, style: AppTypography.messageBody),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AssistantMessage
// ─────────────────────────────────────────────────────────────────────────────

/// Assistant response. No bubble — icon + prose side by side.
class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    super.key,
    required this.text,
    required this.modelIcon,
    this.attachments = const [],
  });
  final String text;
  final Widget modelIcon;
  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modelIcon,
        const SizedBox(width: AppSpacing.assistantIconGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Generated images/videos shown above text
              if (attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: attachments.map((a) => AttachmentThumbnail(a)).toList(),
                ),
                const SizedBox(height: 8),
              ],
              if (text.isNotEmpty) ...[
                MessageContent(text, isStreaming: false),
                const SizedBox(height: 8),
              ],
              _ActionRow(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionBtn(icon: Icons.copy_outlined, tooltip: 'Copy'),
        _ActionBtn(icon: Icons.thumb_up_outlined, tooltip: 'Good response'),
        _ActionBtn(icon: Icons.thumb_down_outlined, tooltip: 'Bad response'),
        _ActionBtn(icon: Icons.refresh, tooltip: 'Regenerate'),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: AppColors.surfaceOverlay,
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: AppColors.textDim),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TypingIndicator
// ─────────────────────────────────────────────────────────────────────────────

/// Three bouncing dots shown while the model is generating.
/// Matches ChatGPT's exact dot animation timing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.modelIcon});
  final Widget modelIcon;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    ));
    _anims = _ctrls.map((c) => Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: c, curve: Curves.easeInOut),
    )).toList();

    // Stagger the start times
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.modelIcon,
        const SizedBox(width: AppSpacing.assistantIconGap),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AnimatedBuilder(
                animation: _anims[i],
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, -3 * _anims[i].value),
                  child: Opacity(
                    opacity: 0.4 + 0.6 * _anims[i].value,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.textDim,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            )),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatInputBox
// ─────────────────────────────────────────────────────────────────────────────

/// The bottom input bar.
///   [+]  [attachment previews] [Message...]  [web] [send/stop]
class ChatInputBox extends StatelessWidget {
  const ChatInputBox({
    super.key,
    required this.controller,
    required this.isGenerating,
    this.onSend,
    this.onStop,
    this.onAddTap,
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
    this.placeholder = 'Message',
    this.webSearchEnabled = false,
    this.onToggleWebSearch,
    // Legacy — kept for callers that only have names
    this.pendingAttachmentNames = const [],
  });

  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onAddTap;
  final List<ChatAttachment> pendingAttachments;
  final ValueChanged<int>? onRemoveAttachment;
  final String placeholder;
  final bool webSearchEnabled;
  final VoidCallback? onToggleWebSearch;
  // Legacy — used when caller hasn't migrated yet
  final List<String> pendingAttachmentNames;

  List<ChatAttachment> get _effectiveAttachments {
    if (pendingAttachments.isNotEmpty) return pendingAttachments;
    // Fallback: wrap names as file attachments so they still show
    return pendingAttachmentNames
        .map((n) => ChatAttachment(
              id: n,
              type: AttachmentType.file,
              name: n,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final attachments = _effectiveAttachments;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.sm,
          AppSpacing.screenH,
          AppSpacing.screenH,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOverlay,
            borderRadius: AppRadius.input,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Attachment preview row
              if (attachments.isNotEmpty) ...[
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _PendingAttachmentPreview(
                      attachment: attachments[i],
                      onRemove: () => onRemoveAttachment?.call(i),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Input row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _InputIconBtn(icon: Icons.add, onTap: onAddTap),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: AppTypography.messageBody,
                      maxLines: 6,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: placeholder,
                        hintStyle: AppTypography.placeholder,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 4),
                        filled: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Web search toggle
                  GestureDetector(
                    onTap: onToggleWebSearch,
                    child: Tooltip(
                      message: webSearchEnabled
                          ? 'Web search on'
                          : 'Web search off',
                      child: Icon(
                        Icons.language_outlined,
                        size: 20,
                        color: webSearchEnabled
                            ? AppColors.accentGreen
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  isGenerating
                      ? _StopButton(onTap: onStop)
                      : _SendButton(onTap: onSend),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a rich preview for a pending attachment in the input bar.
/// Images → actual thumbnail. Videos → dark frame with play icon.
/// Files → pill chip.
class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return _ImagePreview(attachment: attachment, onRemove: onRemove);
    }
    if (attachment.isVideo) {
      return _VideoPreview(attachment: attachment, onRemove: onRemove);
    }
    return _FileChip(attachment: attachment, onRemove: onRemove);
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.attachment, required this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (attachment.thumbnailBytes != null) {
      image = Image.memory(attachment.thumbnailBytes!, fit: BoxFit.cover);
    } else if (attachment.localPath != null) {
      image = Image.network(attachment.localPath!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.image_outlined, color: AppColors.textMuted));
    } else {
      image = const Icon(Icons.image_outlined, color: AppColors.textMuted);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 72, height: 72, child: image),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.surfaceBase,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 13, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.attachment, required this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1D38),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_outlined,
                  color: Color(0xFF7E57C2), size: 24),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  attachment.name,
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.surfaceBase,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 13, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.attachment, required this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceActive,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              attachment.name,
              style: AppTypography.badge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _InputIconBtn extends StatelessWidget {
  const _InputIconBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 20, color: AppColors.textDim),
      ),
    );
  }
}

/// White rounded square — send arrow.
class _SendButton extends StatelessWidget {
  const _SendButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.button,
        ),
        child: const Icon(Icons.arrow_upward, size: 17, color: AppColors.surfaceSidebar),
      ),
    );
  }
}

/// Outlined square — stop generation.
class _StopButton extends StatelessWidget {
  const _StopButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.transparent,
          borderRadius: AppRadius.button,
          border: Border.all(color: AppColors.textDim, width: 1.5),
        ),
        child: const Icon(Icons.stop, size: 14, color: AppColors.textPrimary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ModelPill  (nav bar model selector)
// ─────────────────────────────────────────────────────────────────────────────

/// Tappable model name + chevron in the top nav bar.
class ModelPill extends StatelessWidget {
  const ModelPill({
    super.key,
    required this.modelName,
    required this.modelIcon,
    this.onTap,
  });

  final String modelName;
  final Widget modelIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          modelIcon,
          const SizedBox(width: 6),
          Text(modelName, style: AppTypography.navTitle),
          const SizedBox(width: 3),
          const Icon(Icons.expand_more, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SidebarRow  (history list item)
// ─────────────────────────────────────────────────────────────────────────────

/// One conversation in the history drawer.
class SidebarRow extends StatelessWidget {
  const SidebarRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.isActive = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: AppColors.surfaceOverlay,
        splashColor: AppColors.transparent,
        highlightColor: AppColors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: isActive ? AppColors.surfaceOverlay : AppColors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.sidebarTitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.sidebarSubtitle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ModelRow  (model picker list item)
// ─────────────────────────────────────────────────────────────────────────────

/// One model in the picker sheet.
class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.name,
    required this.description,
    required this.icon,
    this.isSelected = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.isAvailable = true,
    this.onTap,
  });

  final String name;
  final String description;
  final Widget icon;
  final bool isSelected;
  final bool isDownloading;
  final double downloadProgress; // 0.0 – 1.0
  final bool isAvailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: isAvailable ? onTap : null,
        splashColor: AppColors.transparent,
        highlightColor: AppColors.transparent,
        hoverColor: AppColors.surfaceOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH,
            vertical: 11,
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTypography.modelName),
                    Text(description, style: AppTypography.modelDesc),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing() {
    if (isSelected) {
      return const Icon(Icons.check, color: AppColors.accentGreen, size: 18);
    }
    if (isDownloading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          value: downloadProgress,
          strokeWidth: 2.5,
          backgroundColor: AppColors.surfaceOverlay,
          valueColor: const AlwaysStoppedAnimation(AppColors.accentGreen),
        ),
      );
    }
    if (!isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: AppRadius.pill,
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Text('Get', style: AppTypography.badge),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AttachmentThumbnail
// ─────────────────────────────────────────────────────────────────────────────

/// Renders an attachment inline in a message.
/// Images/generated images show as a rounded thumbnail.
/// Files and videos show as a chip with icon + name.
class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail(this.attachment, {super.key});
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage && attachment.thumbnailBytes != null) {
      return _ImageThumb(bytes: attachment.thumbnailBytes!);
    }
    if (attachment.isImage && attachment.localPath != null) {
      return _ImageThumb(path: attachment.localPath!);
    }
    if (attachment.isVideo && attachment.localPath != null) {
      return _VideoThumb(path: attachment.localPath!);
    }
    if (attachment.isVideo) {
      return _FilePill(
        icon: Icons.video_file_outlined,
        name: attachment.name,
        color: const Color(0xFF7E57C2),
      );
    }
    return _FilePill(
      icon: Icons.insert_drive_file_outlined,
      name: attachment.name,
      color: AppColors.textMuted,
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({this.bytes, this.path});
  final Uint8List? bytes;
  final String? path;

  Future<void> _saveToPhotos(BuildContext context) async {
    if (bytes == null) return;
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: false);
        if (!granted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Photo library access denied')),
            );
          }
          return;
        }
      }
      await Gal.putImageBytes(bytes!);
      if (context.mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to Camera Roll'),
            backgroundColor: const Color(0xFF1E3A5F),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  void _showOptions(BuildContext context) {
    if (bytes == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2744),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.white),
              title: const Text('Save to Camera Roll',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _saveToPhotos(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgWidget = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover)
        : Image.asset(path!, fit: BoxFit.cover);

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showOptions(context);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 200,
          height: 200,
          child: imgWidget,
        ),
      ),
    );
  }
}

class _FilePill extends StatelessWidget {
  const _FilePill({required this.icon, required this.name, required this.color});
  final IconData icon;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              name,
              style: AppTypography.badge.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VideoThumb — inline video player in message bubbles
// ─────────────────────────────────────────────────────────────────────────────

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.path});
  final String path;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      _playing ? _ctrl.play() : _ctrl.pause();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _initialized ? _togglePlay : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 200,
          height: 140,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_initialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ctrl.value.size.width,
                    height: _ctrl.value.size.height,
                    child: VideoPlayer(_ctrl),
                  ),
                )
              else
                Container(color: const Color(0xFF0F1D38)),
              if (!_playing || !_initialized)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _initialized
                          ? Icons.play_arrow
                          : Icons.hourglass_empty,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageGenProgress
// ─────────────────────────────────────────────────────────────────────────────

/// Shown in the assistant message while an image is being generated.
class ImageGenProgress extends StatelessWidget {
  const ImageGenProgress({super.key, required this.progress, required this.prompt});
  final double progress;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              backgroundColor: AppColors.surfaceActive,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.accentGreen),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            progress > 0 ? '${(progress * 100).toInt()}%' : 'Starting…',
            style: AppTypography.badge,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Generating image',
              style: AppTypography.userMeta,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
