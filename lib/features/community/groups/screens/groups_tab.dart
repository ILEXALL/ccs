import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show LanguageReactiveState;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/groups/screens/group_directory.dart'
    show PrivateGroupDirectory;

class GroupsTab extends StatefulWidget {
  final List<ChatThreadData> chats;
  final String currentUid;
  final Map<String, int> unreadCountsByChatId;

  const GroupsTab({
    super.key,
    required this.chats,
    required this.currentUid,
    required this.unreadCountsByChatId,
  });

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab>
    with AutomaticKeepAliveClientMixin, LanguageReactiveState {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
      children: [
        PrivateGroupDirectory(
          membershipRevision: widget.chats
              .map(
                (chat) =>
                    '${chat.id}:${chat.isPrivate}:${chat.memberIds.join(',')}',
              )
              .join('|'),
          chats: widget.chats,
          currentUid: widget.currentUid,
          unreadCountsByChatId: widget.unreadCountsByChatId,
        ),
      ],
    );
  }
}
