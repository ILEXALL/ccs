import 'package:ccs_app/app/gates/terms_acceptance_gate.dart';
import 'package:ccs_app/app/gates/profile_region_gate.dart';
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    as app
    show
        activityChatTabIndex,
        activitySectionForNavigation,
        chatActivitySection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccs_app/features/notifications/controllers/in_app_badges.dart';

void main() {
  test('ranking tab has no chat unread section', () {
    for (var index = 0; index < 4; index++) {
      expect(app.chatActivitySection(index), ActivitySection.values[index]);
    }
    expect(app.chatActivitySection(4), isNull);
    final previous = app.activityChatTabIndex;
    addTearDown(() => app.activityChatTabIndex = previous);
    app.activityChatTabIndex = 4;
    expect(app.activitySectionForNavigation(3), isNull);
  });
  testWidgets('accepted terms still require profile region before navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TermsAcceptanceGate(
          loadAcceptance: () async => true,
          child: const ProfileRegionGate(child: Text('Explore')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set your region'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
    expect(find.text('Save and continue'), findsOneWidget);
  });
}
