import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show ChatThreadTile;

class ChatsTab extends StatefulWidget {
  final List<ChatThreadData> chats;
  final String currentUid;
  final Map<String, int> unreadCountsByChatId;

  const ChatsTab({
    super.key,
    required this.chats,
    required this.currentUid,
    required this.unreadCountsByChatId,
  });

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab>
    with AutomaticKeepAliveClientMixin, LanguageReactiveState {
  @override
  bool get wantKeepAlive => true;

  Widget sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CcsText(
            trText(title),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: CcsText(
              '$count',
              style: const TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle('Chats', widget.chats.length),
              if (widget.chats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: CcsText(
                    trText('No direct chats yet.'),
                    style: const TextStyle(color: Colors.white54, height: 1.35),
                  ),
                )
              else
                for (final chat in widget.chats) ...[
                  ChatThreadTile(
                    chat: chat,
                    currentUid: widget.currentUid,
                    unreadCount: widget.unreadCountsByChatId[chat.id] ?? 0,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
