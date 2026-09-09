import 'dart:io';
import 'dart:ui' as ui;
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'only unlocked badges are selectable and failed saves preserve the choice',
    (tester) async {
      String? saved;
      var fail = false;
      final items = [
        for (final id in ['spots.1', 'spots.5', 'spots.10'])
          {
            'id': id,
            'category': 'spots',
            'title': {'en': 'Spots'},
            'xp': 50,
            'threshold': 1,
            'tier': 1,
            'unit': 'count',
            'progress': 1,
            'available': true,
            'status': id == 'spots.10' ? 'locked' : 'confirmed',
          },
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AchievementsScreen(
            language: 'en',
            load: () async => {'enabled': true, 'items': items},
            select: (id) async {
              if (fail) throw StateError('offline');
              saved = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('select-spots.10')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('select-spots.1')));
      await tester.pumpAndSettle();
      expect(saved, 'spots.1');
      expect(find.text('On profile'), findsOneWidget);
      fail = true;
      await tester.tap(find.byKey(const ValueKey('select-spots.5')));
      await tester.pumpAndSettle();
      expect(saved, 'spots.1');
      expect(find.text('Could not save achievement'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Remove from profile'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
    },
  );
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
            'C:/Windows/Fonts/arial.ttf',
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
          {
            'id': category,
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
            'tier': 1,
            'unit': category == 'tourist' ? 'country' : 'count',
            'progress': 0,
            'available': category == 'spots',
            'status': 'locked',
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
