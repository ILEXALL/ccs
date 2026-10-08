import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/progression/controllers/reward_feedback.dart';

void main() {
  testWidgets('XP slides above navigation, stays readable, then slides away', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: rewardMessengerKey,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: const SizedBox.expand(key: Key('map')),
          bottomNavigationBar: const SizedBox(
            height: 62,
            key: Key('navigation'),
          ),
        ),
      ),
    );
    final mapBefore = tester.getRect(find.byKey(const Key('map')));
    handleRewardNotification('test-user', 'readable-xp', {
      'type': 'xp_reward',
      'body': '+25 XP – Spot photo',
      'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final message = find.text('+25 XP – Spot photo');
    final entryTop = tester.getTopLeft(message).dy;
    await tester.pump(const Duration(milliseconds: 300));
    final restingTop = tester.getTopLeft(message).dy;
    expect(entryTop, greaterThan(restingTop));
    expect(tester.widget<Text>(message).style!.color, Colors.white);
    expect(
      tester.getBottomRight(find.byType(SnackBar)).dy,
      closeTo(tester.getTopLeft(find.byKey(const Key('navigation'))).dy, 0.1),
    );
    expect(tester.getRect(find.byKey(const Key('map'))), mapBefore);
    await tester.pump(const Duration(seconds: 3));
    expect(message, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getTopLeft(message).dy, greaterThan(restingTop));
    await tester.pump(const Duration(milliseconds: 200));
    expect(message, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
