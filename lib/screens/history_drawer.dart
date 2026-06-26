import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/chat_providers.dart';
import '../theme/theme.dart';

class HistoryDrawer extends ConsumerWidget {
  const HistoryDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final sessions = state.sessions;

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
            const Divider(height: 1),
            if (sessions.isEmpty)
              const Expanded(child: _EmptyHistory())
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) {
                    final session = sessions[i];
                    return _SessionTile(
                      title: session.displayTitle,
                      isActive: session.id == state.activeSessionId,
                      onTap: () {
                        ref
                            .read(chatControllerProvider.notifier)
                            .selectSession(session.id);
                        Navigator.of(context).pop();
                      },
                      onDelete: () => ref
                          .read(chatControllerProvider.notifier)
                          .deleteSession(session.id),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            _Footer(),
          ],
        ),
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
            child: const Icon(
              Icons.memory,
              color: AppColors.surfaceSidebar,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('PintSizeAi', style: AppTypography.wordmark),
          ),
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
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
              const Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sidebarTitle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (isActive)
                GestureDetector(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: AppColors.textDim,
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 32,
            color: AppColors.textDim,
          ),
          const SizedBox(height: 10),
          Text('No chats yet', style: AppTypography.sidebarSubtitle),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
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
            child: const Icon(Icons.person, size: 18, color: AppColors.white),
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
