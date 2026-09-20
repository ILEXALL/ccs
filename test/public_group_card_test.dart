import 'package:ccs_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'public directory card offers direct joining, member count and public icon',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.appUiPreferences.language = app.AppLanguage.en;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: app.PrivateGroupDirectory(
                currentUid: 'public-card-test',
                membershipRevision: '',
                chats: const [],
                unreadCountsByChatId: const {},
                requestAction: (_) async => {
                  'countryCode': app.currentUserHomeCountryCode(),
                  'visibleGroupIds': ['public'],
                  'groups': [
                    {
                      'id': 'public',
                      'name': 'Public Drivers',
                      'description': 'Drive together',
                      'isPrivate': false,
                      'isMember': false,
                      'isOwner': false,
                      'canMonitor': true,
                      'isBlocked': false,
                      'memberCount': 12,
                      'requestStatus': '',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Public group'), findsOneWidget);
      expect(find.text('Members: 12'), findsOneWidget);
      expect(find.text('Join group'), findsOneWidget);
      expect(find.text('Request to join'), findsNothing);
      expect(find.text('Monitor (read only)'), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('empty descriptions fail before creating a group', () async {
    await expectLater(
      app.createGroupChat(name: 'Group', description: '  ', users: []),
      throwsArgumentError,
    );
    await expectLater(
      app.createGroupChat(name: 'Group', description: 'x' * 1001, users: []),
      throwsArgumentError,
    );
  });
}
