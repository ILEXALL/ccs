import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

app.FriendUserData user(
  String uid,
  String username, {
  String name = '',
  bool deleted = false,
  bool banned = false,
}) => app.FriendUserData(
  uid: uid,
  username: username,
  name: name,
  email: '',
  verified: false,
  role: app.UserRole.user,
  banned: banned,
  deleted: deleted,
);

void main() {
  test(
    'search includes users beyond the first 50 and ranks exact usernames first',
    () {
      final users = [
        for (var i = 0; i < 80; i++) user('u$i', 'a_user_$i'),
        user('partial', 'zzz_driver_extra'),
        user('exact', 'zzz_driver'),
        user('name', 'different', name: 'ZZZ Driver'),
      ];
      expect(
        app.matchingFriendUsers(users, ' @ZZZ_DRIVER ', 'me').map((u) => u.uid),
        ['exact', 'partial'],
      );
      expect(
        app.matchingFriendUsers(users, 'zzz   driver', 'me').single.uid,
        'name',
      );
    },
  );
  test('deleted, actively banned and own accounts are excluded', () {
    final users = [
      user('me', 'alex'),
      user('deleted', 'alex1', deleted: true),
      user('banned', 'alex2', banned: true),
      user('other', 'alex3'),
    ];
    expect(app.matchingFriendUsers(users, 'al', 'me').map((u) => u.uid), [
      'other',
    ]);
    expect(app.matchingFriendUsers(users, '@a', 'me'), isEmpty);
  });
  testWidgets(
    'suggestions start at two characters and reuse one live subscription',
    (tester) async {
      final stream = StreamController<List<app.FriendUserData>>();
      var subscriptions = 0;
      final search = app.FriendUserSearch(
        currentUid: 'me',
        loadUsers: () {
          subscriptions++;
          return stream.stream;
        },
      );
      addTearDown(search.dispose);
      search.search('@a');
      await tester.pump(const Duration(milliseconds: 350));
      expect(subscriptions, 0);
      search.search('@al');
      await tester.pump(const Duration(milliseconds: 300));
      expect(subscriptions, 1);
      stream.add([user('alex', 'alex'), user('alice', 'alice')]);
      await tester.pump();
      expect(search.results.length, 2);
      search.search('ali');
      await tester.pump(const Duration(milliseconds: 300));
      expect(search.results.single.uid, 'alice');
      expect(subscriptions, 1);
      stream.add([user('alice', 'alice'), user('alina', 'alina')]);
      await tester.pump();
      expect(search.results.length, 2);
      await stream.close();
    },
  );
  testWidgets(
    'late data uses the latest query and cannot restore cleared results',
    (tester) async {
      final stream = StreamController<List<app.FriendUserData>>();
      final search = app.FriendUserSearch(
        currentUid: 'me',
        loadUsers: () => stream.stream,
      );
      addTearDown(search.dispose);
      search.search('al');
      await tester.pump(const Duration(milliseconds: 300));
      search.search('bo');
      stream.add([user('alex', 'alex'), user('bob', 'bob')]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(search.results.single.uid, 'bob');
      search.search('b');
      stream.add([user('bob', 'bob')]);
      await tester.pump();
      expect(search.results, isEmpty);
      expect(search.loading, isFalse);
      await stream.close();
    },
  );
  testWidgets('connection errors are exposed and retry reloads users', (
    tester,
  ) async {
    final first = StreamController<List<app.FriendUserData>>();
    final second = StreamController<List<app.FriendUserData>>();
    var attempts = 0;
    final search = app.FriendUserSearch(
      currentUid: 'me',
      loadUsers: () => ++attempts == 1 ? first.stream : second.stream,
    );
    addTearDown(search.dispose);
    search.search('al');
    await tester.pump(const Duration(milliseconds: 300));
    first.addError(Exception('Offline'));
    await tester.pump();
    expect(search.error, isNotNull);
    search.retry();
    await tester.pump(const Duration(milliseconds: 300));
    second.add([user('alex', 'alex')]);
    await tester.pump();
    expect(search.error, isNull);
    expect(search.results.single.uid, 'alex');
    unawaited(first.close());
    unawaited(second.close());
  });
}
