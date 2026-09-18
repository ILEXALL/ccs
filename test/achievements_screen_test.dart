import 'support/preview_font.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'legacy report badges are hidden and excluded from unlocked totals',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            language: 'en',
            load: () async => {
              'enabled': true,
              'items': [
                {
                  'id': 'reports.1',
                  'category': 'reports',
                  'title': {'en': 'Confirmed reports'},
                  'xp': 25,
                  'threshold': 1,
                  'tier': 1,
                  'available': true,
                  'status': 'confirmed',
                },
                {
                  'id': 'reports.5',
                  'category': 'reports',
                  'title': {'en': 'Confirmed reports'},
                  'xp': 50,
                  'threshold': 5,
                  'tier': 2,
                  'available': false,
                  'status': 'locked',
                },
                {
                  'id': 'spots.1',
                  'category': 'spots',
                  'title': {'en': 'Spots'},
                  'xp': 50,
                  'threshold': 1,
                  'tier': 1,
                  'available': true,
                  'status': 'confirmed',
                },
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 1 Unlocked'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('achievement-tile-reports.1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('achievement-tile-reports.5')),
        findsNothing,
      );
      expect(find.text('Confirmed reports'), findsNothing);
      expect(
        find.byKey(const ValueKey('achievement-tile-spots.1')),
        findsOneWidget,
      );
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'compact board separates countries and opens details at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final items = [
          for (var i = 1; i <= 6; i++)
            {
              'id': 'spots.$i',
              'category': 'spots',
              'title': {'en': 'Permanent spots'},
              'xp': 50,
              'threshold': i,
              'tier': 1,
              'progress': 1,
              'available': true,
              'status': i == 1 ? 'confirmed' : 'locked',
            },
          {
            'id': 'tourist.LV',
            'category': 'tourist',
            'title': {'en': 'Latvia'},
            'xp': 75,
            'threshold': 1,
            'tier': 1,
            'progress': 0,
            'available': false,
            'status': 'locked',
            'asset': 'assets/achievements/latvia.png',
          },
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: AchievementsScreen(
              language: 'en',
              load: () async => {
                'enabled': true,
                'selectedId': 'spots.1',
                'items': items,
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final main = find.byKey(const ValueKey('achievement-row-spots'));
        final countries = find.byKey(
          const ValueKey('achievement-board-countries'),
        );
        expect(
          find.descendant(of: main, matching: find.byType(AchievementBadge)),
          findsNWidgets(6),
        );
        expect(
          tester
              .widget<GridView>(countries)
              .childrenDelegate
              .estimatedChildCount,
          1,
        );
        expect(
          find.descendant(of: main, matching: find.text('Latvia')),
          findsNothing,
        );
        expect(
          find.descendant(of: countries, matching: find.text('Latvia')),
          findsOneWidget,
        );
        expect(find.text('Spots'), findsOneWidget);
        expect(find.text('Countries'), findsOneWidget);
        expect(find.text('Show on profile'), findsNothing);
        expect(find.text('Remove from profile'), findsNothing);
        for (final id in ['spots.1', 'spots.2', 'tourist.LV']) {
          await tester.tap(find.byKey(ValueKey('achievement-tile-$id')));
          await tester.pumpAndSettle();
          expect(
            find.text(
              id == 'tourist.LV'
                  ? 'Visit a spot within 100 m in this foreign country'
                  : '${id == 'spots.1' ? 1 : 2} approved permanent spots',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              id == 'spots.1'
                  ? 'Unlocked'
                  : id == 'spots.2'
                  ? '1 / 2'
                  : 'Not available yet',
            ),
            findsOneWidget,
          );
          expect(find.text('Show on profile'), findsNothing);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('achievement loading can retry after an error', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          language: 'en',
          load: () async {
            if (fail) throw StateError('offline');
            return {'enabled': true, 'items': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load achievements'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No unlocked achievements yet'), findsOneWidget);
  });
  testWidgets('board keeps locked and earned badges visible at enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = [
      for (var i = 0; i < 67; i++)
        {
          'id': 'spots.$i',
          'category': 'spots',
          'title': {'en': 'Permanent spots'},
          'xp': 50,
          'threshold': i + 1,
          'tier': 1,
          'available': true,
          'status': i == 0 ? 'confirmed' : 'locked',
          'progress': 1,
        },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: AchievementsScreen(
            language: 'en',
            load: () async => {'enabled': true, 'items': items},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-row-spots')),
        matching: find.byType(AchievementBadge),
      ),
      findsNWidgets(67),
    );
    final earned = find.byKey(const ValueKey('achievement-tile-spots.0'));
    final locked = find.byKey(const ValueKey('achievement-tile-spots.1'));
    expect(
      find.descendant(of: earned, matching: find.byType(ColorFiltered)),
      findsNothing,
    );
    expect(
      find.descendant(of: locked, matching: find.byType(ColorFiltered)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets('XP actions $language fit narrow screen with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: XpProfileActions(
                  language: language,
                  onAchievements: () => calls.add(1),
                  onRewards: () => calls.add(2),
                  onHistory: () => calls.add(3),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final icon in [
        Icons.workspace_premium_outlined,
        Icons.card_giftcard,
        Icons.history,
      ]) {
        await tester.tap(find.byIcon(icon));
      }
      expect(calls, [1, 2, 3]);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'reward guide $language shows progress and retries after errors',
      (tester) async {
        var fail = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: XpRewardsScreen(
              language: language,
              load: () async {
                if (fail) throw StateError('offline');
                return {
                  'items': [
                    {
                      'title': {
                        'en': 'Add a profile photo',
                        'ru': 'Добавить фото профиля',
                        'lv': 'Pievienot profila foto',
                      },
                      'category': 'profile',
                      'xp': 50,
                      'completed': 1,
                      'earnedXp': 50,
                      'pending': 0,
                      'repeatable': false,
                    },
                  ],
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        fail = false;
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();
        expect(find.textContaining(' / 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets('achievement screen $language fits phone and records preview', (
      tester,
    ) async {
      tester.view.reset();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('PreviewFont');
        font.addFont(
          File(
            previewFontPath,
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final items = [
        for (final category in [
          'spots',
          'groups',
          'reports',
          'moderator',
          'tourist',
        ])
          for (var tier = 1; tier <= (category == 'tourist' ? 1 : 5); tier++)
            {
              'id': '$category.$tier',
              'category': category,
              'title': {
                'en': category,
                'ru': {
                  'spots': 'Споты',
                  'groups': 'Владелец группы',
                  'reports': 'Подтверждённые репорты',
                  'moderator': 'Стаж модератора',
                  'tourist': 'Латвия',
                }[category],
                'lv': {
                  'spots': 'Vietas',
                  'groups': 'Grupas īpašnieks',
                  'reports': 'Apstiprināti ziņojumi',
                  'moderator': 'Moderatora stāžs',
                  'tourist': 'Latvija',
                }[category],
              },
              'xp': 100,
              'threshold': 10,
              'tier': tier,
              'unit': category == 'tourist' ? 'country' : 'count',
              'progress': 0,
              'available': category == 'spots',
              'status': category == 'spots' ? 'confirmed' : 'locked',
              if (category == 'tourist')
                'asset': 'assets/achievements/latvia.png',
            },
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'PreviewFont',
            ),
          ),
          home: RepaintBoundary(
            key: key,
            child: AchievementsScreen(
              language: language,
              load: () async => {'enabled': false, 'items': items},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/achievement-previews');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$language.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
