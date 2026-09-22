import 'dart:async';
import 'dart:convert';

import 'package:ccs_app/features/progression/controllers/reward_feedback.dart';
import 'package:ccs_app/features/progression/widgets/level_up_feedback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sounds = <String>[];
  const channel = MethodChannel('ccs/system_notifications');

  setUp(() {
    sounds.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          sounds.add(
            call.method == 'playSound'
                ? call.arguments['sound'] as String
                : 'stop',
          );
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(
    WidgetTester tester,
    Stream<int> levels, {
    String uid = 'feedback',
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rewardNavigatorKey,
        scaffoldMessengerKey: rewardMessengerKey,
        home: LevelUpFeedbackHost(
          key: ValueKey(uid),
          userId: uid,
          levels: levels,
          child: const Scaffold(body: Text('Map')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> level(
    WidgetTester tester,
    StreamController<int> stream,
    int value,
  ) async {
    stream.add(value);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 850));
  }

  testWidgets('XP reason plus level animation and sound happen once', (
    tester,
  ) async {
    final levels = StreamController<int>.broadcast();
    await mount(tester, levels.stream);
    await level(tester, levels, 2);
    expect(find.text('New level unlocked'), findsNothing);
    await level(tester, levels, 3);
    final data = <String, dynamic>{
      'type': 'xp_reward',
      'body': '+200 XP — Event attended',
      'levelUp': 3,
    };
    handleRewardNotification('feedback', 'reward-1', data);
    handleRewardNotification('feedback', 'reward-1', data);
    handleRewardNotification('feedback', 'other-bell', {'type': 'achievement'});
    await tester.pump();
    expect(find.text('+200 XP — Event attended'), findsOneWidget);
    expect(find.text('New level unlocked'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(sounds, ['level']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await level(tester, levels, 3);
    expect(find.text('New level unlocked'), findsNothing);
    expect(sounds, ['level']);
    await tester.pumpWidget(const SizedBox());
    await levels.close();
  });

  testWidgets('background and interrupted celebrations wait for foreground', (
    tester,
  ) async {
    final levels = StreamController<int>.broadcast();
    await mount(tester, levels.stream);
    await level(tester, levels, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await level(tester, levels, 5);
    expect(find.text('New level unlocked'), findsNothing);
    expect(sounds, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('New level unlocked'), findsNothing);
    expect(sounds, ['level', 'stop']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await mount(tester, levels.stream);
    await level(tester, levels, 5);
    expect(find.text('New level unlocked'), findsNothing);
    expect(sounds.where((s) => s == 'level').length, 2);
    await tester.pumpWidget(const SizedBox());
    await levels.close();
  });

  testWidgets(
    'cold launch catches up every new level and persists completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'level_feedback_v1_feedback': jsonEncode({'completed': 5, 'target': 5}),
      });
      final levels = StreamController<int>.broadcast();
      await mount(tester, levels.stream);
      await level(tester, levels, 8);
      expect(find.text('6'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('7'), findsOneWidget);
      // Simulate termination in the middle of a celebration.
      await tester.pumpWidget(const SizedBox());
      await mount(tester, levels.stream);
      expect(find.text('7'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('8'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await level(tester, levels, 8);
      expect(find.text('New level unlocked'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('level_feedback_v1_feedback')!)['completed'],
        8,
      );
      await tester.pumpWidget(const SizedBox());
      await levels.close();
    },
  );

  testWidgets(
    'first use avoids old levels and account switching isolates queues',
    (tester) async {
      final first = StreamController<int>.broadcast();
      final second = StreamController<int>.broadcast();
      await mount(tester, first.stream, uid: 'first');
      await level(tester, first, 17);
      expect(find.text('New level unlocked'), findsNothing);
      await level(tester, first, 18);
      expect(find.text('18'), findsOneWidget);
      await mount(tester, second.stream, uid: 'second');
      await level(tester, second, 2);
      expect(find.text('New level unlocked'), findsNothing);
      await mount(tester, first.stream, uid: 'first');
      expect(find.text('18'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await first.close();
      await second.close();
    },
  );
}
