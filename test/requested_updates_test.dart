import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/features/community/forum/models/topic_activity.dart';
import 'package:ccs_app/features/events/models/forum_event_schedule.dart';
import 'package:ccs_app/features/notifications/data/visible_chat.dart';
import 'package:ccs_app/features/map/controllers/navigation_motion.dart';
import 'package:ccs_app/shared/utils/date_formatting.dart';
import 'package:ccs_app/core/localization/app_language.dart';

void main() {
  test(
    '30-day inactivity uses reply or creation, preserves unknown legacy dates',
    () {
      final now = DateTime.utc(2026, 11, 19);
      final cutoff = now.subtract(const Duration(days: 30));
      expect(
        forumTopicHasRecentActivity({
          'createdAt': Timestamp.fromDate(cutoff),
        }, now),
        false,
      );
      expect(
        forumTopicHasRecentActivity({
          'createdAt': cutoff.millisecondsSinceEpoch + 1,
        }, now),
        true,
      );
      expect(
        forumTopicHasRecentActivity({
          'createdAt': 1,
          'lastReplyAt': Timestamp.fromDate(now),
        }, now),
        true,
      );
      expect(forumTopicHasRecentActivity({}, now), true);
    },
  );
  test('event instants with source offsets format in viewer timezone', () {
    for (final instant in [
      DateTime.parse('2026-01-15T19:00:00+02:00'),
      DateTime.parse('2026-07-15T19:00:00+03:00'),
    ]) {
      final local = instant.toLocal();
      expect(
        formatClockTime(instant),
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}',
      );
      expect(formatShortDateTime(instant), formatShortDateTime(local));
    }
  });
  test(
    'legacy forum schedule is rebuilt from timestamps without changing prose',
    () {
      appUiPreferences.language = AppLanguage.en;
      final start = DateTime.utc(2026, 7, 15, 16);
      final end = start.add(const Duration(hours: 3));
      final text = localizedForumEventDescription({
        'description':
            'Meet at https://example.com\n\nLocation: Riga\n\nStarts at: 15.07 19:00\n\nEnds at: 15.07 22:00',
        'temporarySpotStartsAt': Timestamp.fromDate(start),
        'temporarySpotExpiresAt': Timestamp.fromDate(end),
      });
      expect('Starts at'.allMatches(text).length, 1);
      expect(text, contains('Meet at https://example.com\n\nLocation: Riga'));
      expect(text, contains('Starts at: ${formatShortDateTime(start)}'));
    },
  );
  test(
    'fallback camera keeps low-speed scale and zooms out further on highways',
    () {
      expect(speedFollowZoom(16.35, 0), 16.35);
      expect(speedFollowZoom(16.35, 30 / 3.6), 16.35);
      expect(speedFollowZoom(16.35, 100 / 3.6), closeTo(14.765, 0.001));
      expect(speedFollowZoom(16.35, double.nan), 16.35);
    },
  );
  testWidgets(
    'visibility follows stacked routes, suppressing only the current chat',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(visibleChatRoutes.clear);
      Widget page(String id) => Builder(
        builder: (context) {
          visibleChatRoutes[id] = () =>
              ModalRoute.of(context)?.isCurrent == true ? id : null;
          return const Scaffold();
        },
      );
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: page('a')),
      );
      expect(chatIsVisible('a'), true);
      expect(chatIsVisible('b'), false);
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('b')),
      );
      await tester.pumpAndSettle();
      expect(chatIsVisible('a'), false);
      expect(chatIsVisible('b'), true);
      visibleChatRoutes.remove('b');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(chatIsVisible('a'), true);
      expect(chatIsVisible(''), false);
    },
  );
}
