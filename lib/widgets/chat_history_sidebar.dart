import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../controllers/chat_history_controller.dart';
import '../models/conversation_model.dart';
import '../pages/chat_page.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';

/// ChatGPT-style chat-history sidebar. Collapsible via [open]/[onToggle].
/// When open it shows "+ New chat", the recent thread list (grouped by day),
/// and rename/delete controls. Degrades gracefully when history is
/// unavailable (Supabase down / unsigned).
class ChatHistorySidebar extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;

  const ChatHistorySidebar({
    super.key,
    required this.open,
    required this.onToggle,
  });

  static const double _width = 280;

  @override
  Widget build(BuildContext context) {
    final controller = ChatHistoryController.instance;

    // Single stable widget that animates between closed (0px) and open
    // (280px). The content is always mounted and clipped, so the panel
    // slides in/out horizontally instead of appearing/disappearing.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: open ? _width : 0,
      decoration: BoxDecoration(
        color: AppColors.sideNav,
        border: Border(right: BorderSide(color: AppColors.searchBarBorder)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _width,
          height: double.infinity,
          child: _buildContent(context, controller),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, ChatHistoryController controller) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, controller),
          if (!SupabaseService.ready)
            const _AvailabilityNote()
          else
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _buildList(context, controller),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ChatHistoryController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: onToggle,
            tooltip: 'Close Chat History',
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, ChatHistoryController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _NewChatButton(
            onPressed: () async {
              await controller.startNewChat();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatPage()),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: const Text(
            'RECENT',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: _conversationList(context, controller),
        ),
      ],
    );
  }

  Widget _conversationList(
      BuildContext context, ChatHistoryController controller) {
    if (controller.loadingConversations) {
      return const Skeletonizer(enabled: true, child: _SkeletonItems());
    }

    if (controller.errorLoadingConversations) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Chat history is temporarily unavailable.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    if (controller.conversations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No chats yet.\nStart a conversation to see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final groups = _groupByDay(controller.conversations);
    final tiles = <Widget>[];
    groups.forEach((label, items) {
      tiles.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
      for (final c in items) {
        tiles.add(_ConversationTile(
          conversation: c,
          isActive: c.id == controller.activeConversationId,
          onTap: () => _openConversation(context, controller, c),
          onRename: () => _rename(context, controller, c),
          onDelete: () => _delete(context, controller, c),
        ));
      }
    });
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: tiles,
    );
  }

  void _openConversation(BuildContext context,
      ChatHistoryController controller, ConversationModel c) {
    controller.openConversation(c.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(conversationId: c.id)),
    );
  }

  Future<void> _rename(BuildContext context, ChatHistoryController controller,
      ConversationModel c) async {
    final textController = TextEditingController(text: c.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.sideNav,
        title: const Text('Rename chat',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'New title',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, textController.text),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await controller.renameConversation(c.id, newTitle.trim());
    }
  }

  Future<void> _delete(BuildContext context, ChatHistoryController controller,
      ConversationModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.sideNav,
        title: const Text('Delete chat?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '"${c.title}" and its messages will be permanently removed.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteConversation(c.id);
    }
  }

  Map<String, List<ConversationModel>> _groupByDay(
      List<ConversationModel> conversations) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 6));
    final grouped = <String, List<ConversationModel>>{
      'Today': [],
      'Yesterday': [],
      'Previous 7 days': [],
      'Older': [],
    };
    for (final c in conversations) {
      final d = DateTime(
        c.updatedAt.year,
        c.updatedAt.month,
        c.updatedAt.day,
      );
      if (!d.isBefore(today)) {
        grouped['Today']!.add(c);
      } else if (!d.isBefore(yesterday)) {
        grouped['Yesterday']!.add(c);
      } else if (!d.isBefore(weekAgo)) {
        grouped['Previous 7 days']!.add(c);
      } else {
        grouped['Older']!.add(c);
      }
    }
    grouped.removeWhere((_, items) => items.isEmpty);
    grouped.forEach((_, items) {
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    });
    return grouped;
  }
}

class _NewChatButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NewChatButton({required this.onPressed});

@override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New Chat',
      child: Semantics(
        button: true,
        label: 'New Chat',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.searchBarBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'New chat',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  Spacer(),
                  Icon(Icons.edit_outlined, color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive
            ? Colors.white.withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.chat_outlined,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                _tileMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tileMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert,
          color: Colors.white38, size: 16),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: AppColors.sideNav,
      onSelected: (value) {
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('Rename', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonItems extends StatelessWidget {
  const _SkeletonItems();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Skeletonizer(
                enabled: true,
                child: SizedBox(
                  width: double.infinity,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AvailabilityNote extends StatelessWidget {
  const _AvailabilityNote();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chat history is temporarily unavailable.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ),
    );
  }
}