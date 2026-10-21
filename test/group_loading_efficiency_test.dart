import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/community/chats/models/chat_thread.dart';
import 'package:ccs_app/features/community/groups/screens/groups_tab.dart';
import 'package:ccs_app/features/community/groups/widgets/group_settings_content.dart';
import 'package:ccs_app/features/community/groups/controllers/group_settings_view_state.dart';

ChatThreadData chat(String id, List<String> members, {bool group = true}) =>
    ChatThreadData(
      id: id,
      isGroup: group,
      name: id,
      memberIds: members,
      memberUsernames: const [],
      lastMessage: '',
      updatedAtMillis: 0,
    );

class Host implements GroupSettingsViewState, GroupSettingsControllerActions {
  ChatThreadData data = chat('a', ['one']);
  @override
  GroupSettingsControllerActions get controller => this;
  @override
  ChatThreadData get localChatData => data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('message reorder and direct chats do not refresh group directory', () {
    final a = chat('a', ['one', 'two']);
    final b = chat('b', ['three']);
    expect(
      groupMembershipRevision([a, b]),
      groupMembershipRevision([
        b,
        chat('a', ['two', 'one']),
        chat('dm', ['four'], group: false),
      ]),
    );
    expect(
      groupMembershipRevision([a, b]),
      isNot(
        groupMembershipRevision([
          a,
          chat('b', ['three', 'four']),
        ]),
      ),
    );
  });

  test(
    'member request survives rebuilds and reloads after membership changes',
    () async {
      final host = Host();
      var requests = 0;
      final content = GroupSettingsContent(
        host,
        loadMembers: (_) async {
          requests++;
          return [];
        },
      );
      final first = content.membersFuture();
      expect(identical(first, content.membersFuture()), isTrue);
      await first;
      await content.membersFuture();
      expect(requests, 1);
      host.data = chat('a', ['one', 'two']);
      await content.membersFuture();
      expect(requests, 2);
    },
  );
}
