import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/moderation/screens/admin_ban_history_screen.dart';

void main() {
  testWidgets(
    'expired bans only appear in history, with recorded reasons and dates',
    (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminBanHistoryScreen(
            request: (_) async => {
              'cursor': null,
              'entries': [
                {
                  'uid': 'old',
                  'username': 'expired_driver',
                  'country': 'LV',
                  'active': false,
                  'expiresAt': now - 1000,
                  'history': [
                    {
                      'bannedAt': now - 2000,
                      'expiresAt': now - 1000,
                      'reason': 'Spam',
                      'bannedBy': 'review_admin',
                      'bannedByUid': 'admin1',
                      'liftedAt': null,
                    },
                  ],
                },
                {
                  'uid': 'current',
                  'username': 'active_driver',
                  'country': 'LV',
                  'active': true,
                  'expiresAt': now + 60000,
                  'history': [
                    {
                      'bannedAt': now - 2000,
                      'expiresAt': now + 60000,
                      'reason': 'Abuse',
                      'liftedAt': null,
                    },
                  ],
                },
              ],
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('@active_driver'), findsOneWidget);
      expect(find.textContaining('@expired_driver'), findsNothing);
      await tester.tap(find.text('Previously banned list'));
      await tester.pump();
      expect(find.textContaining('@active_driver'), findsNothing);
      expect(find.textContaining('@expired_driver'), findsOneWidget);
      expect(find.text('Recorded bans: 1'), findsOneWidget);
      expect(find.text('Reason: Spam'), findsOneWidget);
      expect(find.text('Banned by: @review_admin'), findsOneWidget);
      expect(find.textContaining('Expired:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
