import 'dart:async';
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> badge(String id, String status) => {
  'id': id,
  'category': 'spots',
  'title': {'en': id},
  'status': status,
  'xp': 10,
  'threshold': 1,
  'tier': 1,
  'available': true,
};

void main() {
  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('achievement-tile-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('select, replace, remove and restore saved selection', (
    tester,
  ) async {
    final saved = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          language: 'en',
          load: () async => {
            'enabled': true,
            'selectedId': 'spots.1',
            'items': [
              badge('spots.1', 'confirmed'),
              badge('spots.2', 'confirmed'),
            ],
          },
          onSelect: (id) async {
            saved.add(id);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester, 'spots.1');
    expect(find.text('Remove from profile'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await open(tester, 'spots.2');
    await tester.tap(find.text('Show on profile'));
    await tester.pumpAndSettle();
    expect(saved, ['spots.2']);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await open(tester, 'spots.1');
    expect(find.text('Show on profile'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await open(tester, 'spots.2');
    await tester.tap(find.text('Remove from profile'));
    await tester.pumpAndSettle();
    expect(saved, ['spots.2', null]);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets(
    'locked achievements and public boards have no selection action',
    (tester) async {
      for (final public in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: AchievementsScreen(
              key: ValueKey(public),
              language: 'en',
              load: () async => {
                'enabled': true,
                'items': [badge('spots.1', public ? 'confirmed' : 'locked')],
              },
              onSelect: public ? null : (_) async => fail('Locked selection'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await open(tester, 'spots.1');
        expect(find.text('Show on profile'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'pending save blocks duplicates and failure preserves selection',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            language: 'en',
            load: () async => {
              'enabled': true,
              'items': [badge('spots.1', 'confirmed')],
            },
            onSelect: (_) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester, 'spots.1');
      await tester.tap(find.text('Show on profile'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      expect(find.text('Show on profile'), findsOneWidget);
      expect(find.text('Remove from profile'), findsNothing);
    },
  );

  testWidgets('profile displays the badge and localized name at narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: FeaturedAchievement(
              language: 'ru',
              item: {
                ...badge('spots.1', 'confirmed'),
                'title': {'en': 'First spot', 'ru': 'Первый спот'},
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Первый спот'), findsOneWidget);
    expect(find.text('Достижение в профиле'), findsOneWidget);
    expect(find.byType(AchievementBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
