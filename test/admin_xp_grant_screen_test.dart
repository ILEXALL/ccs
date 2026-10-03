import 'dart:convert';
import 'package:ccs_app/features/moderation/screens/admin_xp_grant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'user menu recipient is prefilled and cannot be replaced by a reused username',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdminXpGrantScreen(
            currentActorId: () => 'admin',
            selectedUsername: 'Driver',
            selectedUserId: 'original',
            request: (action, [extra = const {}]) async {
              actions.add(action);
              return {'username': 'Driver', 'userId': 'different-account'};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'Driver');
      expect(field.enabled, false);
      await tester.enterText(find.byType(TextField).at(2), 'Community support');
      await tester.tap(find.widgetWithText(FilledButton, 'Grant XP'));
      await tester.pumpAndSettle();
      expect(actions, ['admin_xp_grant_target']);
      expect(
        find.textContaining('now belongs to another account'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'requires a reason, confirms recipient, and retains request after lost response',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Map<String, dynamic>>[];
      var fail = true;
      Future<Map<String, dynamic>> request(
        String action, [
        Map<String, dynamic> extra = const {},
      ]) async {
        if (action == 'admin_xp_grant_target') {
          return {'userId': 'recipient', 'username': 'Driver'};
        }
        requests.add(Map.of(extra));
        if (fail) throw Exception('Response lost after commit');
        return {
          'userId': 'recipient',
          'username': 'Driver',
          'amount': 1000,
          'xpTotal': 8796,
          'level': 19,
          'duplicate': true,
        };
      }

      Widget screen() => MaterialApp(
        home: AdminXpGrantScreen(
          request: request,
          currentActorId: () => 'admin',
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Driver');
      await tester.tap(find.widgetWithText(FilledButton, 'Grant XP'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(
        find.text('Enter a username, 1–3000 XP and a reason.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).at(2),
        'Helped at a community event',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Grant XP'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reason: Helped at a community event'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Grant XP'),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString('admin_xp_grant_pending_admin')!,
      );
      expect(saved['requestId'], requests.single['requestId']);
      await tester.pumpWidget(const SizedBox());
      fail = false;
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retry pending grant'),
      );
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[1], requests[0]);
      expect(prefs.getString('admin_xp_grant_pending_admin'), isNull);
      expect(find.textContaining('Total: 8796 XP, level 19'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit rejection lets admin correct input; changed session cannot submit',
    (tester) async {
      final pending = {
        'username': 'Driver',
        'userId': 'recipient',
        'amount': 1000,
        'reason': 'Thanks',
        'requestId': 'retry-request',
      };
      SharedPreferences.setMockInitialValues({
        'admin_xp_grant_pending_admin': jsonEncode(pending),
      });
      String? actor = 'admin';
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminXpGrantScreen(
            currentActorId: () => actor,
            request: (action, [extra = const {}]) async {
              calls++;
              return {
                'rejected': true,
                'message': 'Recipient is blocked or being deleted',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      actor = 'other';
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retry pending grant'),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      actor = 'admin';
      await tester.tap(
        find.widgetWithText(FilledButton, 'Retry pending grant'),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        true,
      );
      expect(
        find.text('Recipient is blocked or being deleted'),
        findsOneWidget,
      );
    },
  );
}
