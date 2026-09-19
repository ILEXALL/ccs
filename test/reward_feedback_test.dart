import 'package:ccs_app/reward_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new XP shows reason, level animation and sound once', (tester) async {
    final sounds = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ccs/system_notifications'), (call) async {
        if (call.method == 'playSound') sounds.add(call.arguments['sound'] as String);
        return null;
      });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: rewardNavigatorKey, scaffoldMessengerKey: rewardMessengerKey,
      home: const Scaffold(body: Center(child: Text('Map'))),
    ));
    final data = <String, dynamic>{'type': 'xp_reward', 'body': '+200 XP — Event attended', 'levelUp': 3};
    handleRewardNotification('feedback-test', 'reward-1', data);
    handleRewardNotification('feedback-test', 'reward-1', data);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('+200 XP — Event attended'), findsOneWidget);
    expect(find.text('LEVEL UP'), findsOneWidget);
    expect(sounds, ['level']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('LEVEL UP'), findsNothing);
    expect(tester.takeException(), isNull);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ccs/system_notifications'), null);
  });
}
