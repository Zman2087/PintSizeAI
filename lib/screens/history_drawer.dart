import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/chat_message.dart';
import '../features/chat/chat_providers.dart';
import '../theme/theme.dart';

class HistoryDrawer extends ConsumerStatefulWidget {
  const HistoryDrawer({super.key});

  @override
  ConsumerState<HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends ConsumerState<HistoryDrawer> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final allSessions = chatState.sessions;
    final filtered = _query.isEmpty
        ? allSessions
        : allSessions.where((s) {
            final q = _query.toLowerCase();
            if (s.displayTitle.toLowerCase().contains(q)) return true;
            return s.messages
                .any((m) => m.content.toLowerCase().contains(q));
          }).toList();

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surfaceSidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onNewChat: () {
              ref.read(chatControllerProvider.notifier).newChat();
              Navigator.of(context).pop();
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
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: AppColors.textDim),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setState(() => _query = ''),
                          child: const Icon(Icons.close,
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
                      onTap: () {
                        ref
                            .read(chatControllerProvider.notifier)
                            .selectSession(session.id);
                        Navigator.of(context).pop();
                      },
                      onDelete: () => ref
                          .read(chatControllerProvider.notifier)
                          .deleteSession(session.id),
                      onExport: () => _export(session.messages,
                          session.displayTitle),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            const _Footer(),
          ],
        ),
      ),
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
            child: const Icon(Icons.memory,
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
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;

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
              const Icon(Icons.chat_bubble_outline,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: AppTypography.sidebarTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
              if (isActive)
                GestureDetector(
                  onTap: () => _showOptions(context),
                  child: const Padding(
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
              leading:
                  const Icon(Icons.share_outlined, color: AppColors.textMuted),
              title: Text('Export / Share', style: AppTypography.sidebarTitle),
              onTap: () {
                Navigator.pop(context);
                onExport();
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
