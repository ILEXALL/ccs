import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;
import 'package:ccs_app/in_app_badges.dart';

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
  testWidgets('main navigation stays locked until profile region is complete', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: app.MainScreen()));
    expect(find.text('Set your region'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
    expect(find.text('Save and continue'), findsOneWidget);
  });
}
