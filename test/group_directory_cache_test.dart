import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/main.dart' as app;

Map<String, dynamic> directory(String name) => {
  'countryCode': app.currentUserHomeCountryCode(),
  'visibleGroupIds': ['group'],
  'groups': [
    {
      'id': 'group',
      'name': name,
      'description': '',
      'photoUrl': '',
      'isMember': false,
      'isOwner': false,
      'canMonitor': false,
      'requestStatus': '',
    },
  ],
};

String cacheKey(String uid) => app.GroupDirectoryCache.key(
  uid,
  app.currentUserHomeCountryCode(),
  '${app.currentUser.role.name}:${app.currentUser.globalChatModerator}',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    app.appUiPreferences.language = app.AppLanguage.en;
  });

  test(
    'disk cache restores a list after restart and rejects expired/corrupt data',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'restart-test',
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'data': directory('Saved group'),
        }),
      );
      expect(
        (await app.GroupDirectoryCache.read('restart-test'))?['groups'],
        isNotEmpty,
      );
      await prefs.setString(
        'expired-test',
        jsonEncode({'savedAt': 0, 'data': directory('Old')}),
      );
      await prefs.setString('corrupt-test', 'broken json');
      expect(await app.GroupDirectoryCache.read('expired-test'), isNull);
      expect(await app.GroupDirectoryCache.read('corrupt-test'), isNull);
    },
  );

  test('cache is separated by account, country, and access role', () async {
    final key = app.GroupDirectoryCache.key('alice', 'LV', 'user:false');
    await app.GroupDirectoryCache.write(key, directory('Alice'));
    expect(app.GroupDirectoryCache.peek(key), isNotNull);
    expect(
      await app.GroupDirectoryCache.read(
        app.GroupDirectoryCache.key('bob', 'LV', 'user:false'),
      ),
      isNull,
    );
    expect(
      await app.GroupDirectoryCache.read(
        app.GroupDirectoryCache.key('alice', 'LT', 'user:false'),
      ),
      isNull,
    );
    expect(
      await app.GroupDirectoryCache.read(
        app.GroupDirectoryCache.key('alice', 'LV', 'admin:false'),
      ),
      isNull,
    );
  });

  testWidgets('saved cards appear before the server finishes and then update', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    await app.GroupDirectoryCache.write(
      cacheKey('cached-user'),
      directory('Saved group'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.PrivateGroupDirectory(
            membershipRevision: '',
            chats: const [],
            currentUid: 'cached-user',
            unreadCountsByChatId: const {},
            requestAction: (_) => response.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Saved group'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    response.complete(directory('Fresh group'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh group'), findsOneWidget);
    expect(find.text('Saved group'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed background refresh keeps saved cards visible', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    await app.GroupDirectoryCache.write(
      cacheKey('offline-user'),
      directory('Offline group'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.PrivateGroupDirectory(
            membershipRevision: '',
            chats: const [],
            currentUid: 'offline-user',
            unreadCountsByChatId: const {},
            requestAction: (_) => response.future,
          ),
        ),
      ),
    );
    response.completeError(Exception('Offline'));
    await tester.pumpAndSettle();
    expect(find.text('Offline group'), findsOneWidget);
    expect(find.text('Showing saved groups. Tap to retry.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
