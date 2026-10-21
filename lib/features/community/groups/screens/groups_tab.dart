import 'dart:convert';
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
          membershipRevision: groupMembershipRevision(widget.chats),
          chats: widget.chats,
          currentUid: widget.currentUid,
          unreadCountsByChatId: widget.unreadCountsByChatId,
        ),
      ],
    );
  }
}

// Message activity reorders chats; it must not reload the group directory.
String groupMembershipRevision(List<ChatThreadData> chats) {
  final groups = chats.where((chat) => chat.isGroup).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode([
    for (final chat in groups)
      [chat.id, chat.isPrivate, (List.of(chat.memberIds)..sort())],
  ]);
}
