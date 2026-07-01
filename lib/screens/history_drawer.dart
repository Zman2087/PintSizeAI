import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../features/chat/chat_message.dart';
import '../features/chat/chat_providers.dart';
import '../features/chat/chat_export_service.dart';
import '../theme/theme.dart';

class HistoryDrawer extends ConsumerStatefulWidget {
  const HistoryDrawer({super.key, this.embedded = false});

  /// When true, renders without a Drawer wrapper (for iPad split layout).
  final bool embedded;

  @override
  ConsumerState<HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends ConsumerState<HistoryDrawer> {
  String _query = '';
  final _exportService = ChatExportService();

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final allSessions = chatState.sessions;
    final matched = _query.isEmpty
        ? [...allSessions]
        : allSessions.where((s) {
            final q = _query.toLowerCase();
            if (s.displayTitle.toLowerCase().contains(q)) return true;
            return s.messages
                .any((m) => m.content.toLowerCase().contains(q));
          }).toList();
    // Pinned sessions float to the top, preserving relative order otherwise.
    final filtered = [
      ...matched.where((s) => s.pinned),
      ...matched.where((s) => !s.pinned),
    ];

    final isEmbedded = widget.embedded;

    void onSessionTap(String id) {
      ref.read(chatControllerProvider.notifier).selectSession(id);
      if (!isEmbedded) Navigator.of(context).pop();
    }

    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onNewChat: () {
            ref.read(chatControllerProvider.notifier).newChat();
            if (!isEmbedded) Navigator.of(context).pop();
          }),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: AppTypography.sidebarTitle,
              decoration: InputDecoration(
                hintText: 'Search conversations…',
                hintStyle: AppTypography.sidebarSubtitle,
                prefixIcon: Icon(Icons.search,
                    size: 16, color: AppColors.textDim),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() => _query = ''),
                        child: Icon(Icons.close,
                            size: 14, color: AppColors.textDim),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceOverlay,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1),
          if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _query.isEmpty ? 'No chats yet' : 'No results',
                  style: AppTypography.sidebarSubtitle,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final session = filtered[i];
                  return _SessionTile(
                    title: session.displayTitle,
                    isActive: session.id == chatState.activeSessionId,
                    isBranch: session.branchedFromSessionId != null,
                    isPinned: session.pinned,
                    onTap: () => onSessionTap(session.id),
                    onDelete: () => ref
                        .read(chatControllerProvider.notifier)
                        .deleteSession(session.id),
                    onExport: () => _export(session.messages,
                        session.displayTitle),
                    onExportPdf: () => _exportPdf(session.messages,
                        session.displayTitle),
                    onPin: () => ref
                        .read(chatControllerProvider.notifier)
                        .togglePin(session.id),
                    onRename: () => _showRenameDialog(
                        session.id, session.displayTitle),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          const _Footer(),
        ],
      ),
    );

    if (isEmbedded) return body;

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surfaceSidebar,
      child: body,
    );
  }

  void _export(List<ChatMessage> messages, String title) {
    final buf = StringBuffer();
    buf.writeln('# $title');
    buf.writeln('Exported from PintSizeAi\n');
    for (final m in messages) {
      final role = m.isUser ? 'You' : 'AI';
      buf.writeln('**$role:** ${m.content}\n');
    }
    Share.share(buf.toString(), subject: title);
  }

  void _exportPdf(List<ChatMessage> messages, String title) {
    _exportService.shareAsPdf(messages, title);
  }

  void _showRenameDialog(String sessionId, String currentTitle) {
    final ctrl = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOverlay,
        title: Text('Rename chat', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Chat name',
            hintStyle: TextStyle(color: AppColors.textDim),
          ),
          onSubmitted: (v) {
            ref.read(chatControllerProvider.notifier).renameSession(sessionId, v);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(chatControllerProvider.notifier)
                  .renameSession(sessionId, ctrl.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save',
                style: TextStyle(color: AppColors.accentGreen)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.memory,
                color: AppColors.surfaceSidebar, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('PintSizeAi', style: AppTypography.wordmark)),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'New chat',
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.title,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
    required this.onExportPdf,
    required this.onPin,
    required this.onRename,
    this.isBranch = false,
    this.isPinned = false,
  });

  final String title;
  final bool isActive;
  final bool isBranch;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onExportPdf;
  final VoidCallback onPin;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showOptions(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? AppColors.surfaceOverlay : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isBranch ? Icons.call_split : Icons.chat_bubble_outline,
                size: 14,
                color: isBranch ? const Color(0xFF34D399) : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: AppTypography.sidebarTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
              if (isPinned)
                Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.push_pin, size: 12, color: AppColors.textDim),
                ),
              if (isActive)
                GestureDetector(
                  onTap: () => _showOptions(context),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz,
                        size: 14, color: AppColors.textDim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline,
                  color: AppColors.textMuted),
              title: Text('Rename', style: AppTypography.sidebarTitle),
              onTap: () {
                Navigator.pop(context);
                onRename();
              },
            ),
            ListTile(
              leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: AppColors.textMuted),
              title: Text(isPinned ? 'Unpin' : 'Pin to top',
                  style: AppTypography.sidebarTitle),
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.share_outlined, color: AppColors.textMuted),
              title: Text('Share as text', style: AppTypography.sidebarTitle),
              onTap: () {
                Navigator.pop(context);
                onExport();
              },
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.textMuted),
              title: Text('Export as PDF', style: AppTypography.sidebarTitle),
              onTap: () {
                Navigator.pop(context);
                onExportPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Color(0xFFEF4444)),
              title: Text('Delete',
                  style: AppTypography.sidebarTitle
                      .copyWith(color: const Color(0xFFEF4444))),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accentGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.person, size: 18, color: AppColors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Private mode', style: AppTypography.username),
              Text('All local · no cloud', style: AppTypography.userMeta),
            ],
          ),
        ],
      ),
    );
  }
}
