import 'package:ccs_app/features/auth/data/auth_state.dart'
    as app
    show currentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' as app show AppUser;
import 'package:ccs_app/features/moderation/data/forum_review_lease.dart'
    as app
    show ForumReviewLease;
import 'package:ccs_app/features/moderation/screens/forum_moderation_screen.dart'
    as app
    show ForumModerationScreen;
import 'package:ccs_app/shared/models/user_role.dart' as app show UserRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final previous = app.currentUser;
  tearDown(() => app.currentUser = previous);
  for (final blocked in [false, true]) {
    testWidgets('automatic entry, blocked=$blocked, no country selector', (
      tester,
    ) async {
      app.currentUser = const app.AppUser(
        uid: 'reviewer',
        name: 'Reviewer',
        username: 'reviewer',
        email: '',
        role: app.UserRole.moderator,
        country: 'Estonia',
        city: 'Tallinn',
        moderatorCountryCodes: {'EE'},
      );
      final calls = <String>[];
      final lease = app.ForumReviewLease(
        userId: 'reviewer',
        requestAction: (body) async {
          calls.add(body['operation'] as String);
          expect(body.containsKey('countryCode'), isFalse);
          if (body['operation'] == 'release') return {'released': true};
          return {
            'acquired': !blocked,
            'renewed': !blocked,
            'blocked': blocked,
            'reviewerUsername': 'alice',
            'topics': <Map<String, dynamic>>[],
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: app.ForumModerationScreen(leaseFactory: () => lease)),
      );
      await tester.pumpAndSettle();
      expect(calls, ['acquire']);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(
        find.textContaining('@alice'),
        blocked ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('No topics awaiting review'),
        blocked ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls.last, 'release');
    });
  }
  testWidgets('new overlap hides topics and names the blocker on renewal', (
    tester,
  ) async {
    app.currentUser = const app.AppUser(
      uid: 'reviewer',
      name: 'Reviewer',
      username: 'reviewer',
      email: '',
      role: app.UserRole.admin,
      country: 'Latvia',
      city: 'Riga',
    );
    final lease = app.ForumReviewLease(
      userId: 'reviewer',
      requestAction: (body) async {
        if (body['operation'] == 'acquire')
          return {
            'acquired': true,
            'topics': [
              {
                'id': 'topic',
                'title': 'Pending topic',
                'description': 'Review this',
                'authorName': 'driver',
                'categoryId': 'general',
              },
            ],
          };
        if (body['operation'] == 'release') return {'released': true};
        return {'renewed': false, 'blocked': true, 'reviewerUsername': 'alice'};
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: app.ForumModerationScreen(leaseFactory: () => lease)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pending topic'), findsOneWidget);
    await lease.renew();
    await tester.pump();
    expect(find.text('Pending topic'), findsNothing);
    expect(find.textContaining('@alice'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
