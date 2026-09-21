import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'support/preview_font.dart';
import 'package:ccs_app/admin_rewards_screen.dart';
import 'package:ccs_app/weekly_rewards_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render active weekly and admin rewards', (tester) async {
    tester.view.physicalSize = const Size(390, 1150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('PreviewFont');
      font.addFont(
        File(previewFontPath).readAsBytes().then(ByteData.sublistView),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'PreviewFont',
          ),
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(title: const Text('Награды')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: WeeklyRewardsSection(
                language: 'ru',
                onOpenSpot: (_) {},
                weekly: {
                  'status': 'active',
                  'totalXp': 600,
                  'consumedXp': 2900,
                  'limit': 3000,
                  'pendingXp': 250,
                  'items': [
                    {
                      'title': {'ru': 'Посетить два разных спота'},
                      'xp': 150,
                      'difficulty': 0,
                      'target': 2,
                      'progress': 2,
                      'status': 'confirmed',
                    },
                    {
                      'title': {'ru': 'Посетить разные споты в два разных дня'},
                      'xp': 200,
                      'difficulty': 1,
                      'target': 2,
                      'progress': 1,
                      'status': 'active',
                    },
                    {
                      'title': {'ru': 'Посетить споты трёх разных категорий'},
                      'xp': 250,
                      'difficulty': 2,
                      'target': 3,
                      'progress': 3,
                      'status': 'pending',
                    },
                  ],
                  'adminItems': [
                    {
                      'id': 'meet',
                      'title': {'ru': 'Посети встречу CCS'},
                      'xp': 200,
                      'target': 1,
                      'progress': 0,
                      'status': 'active',
                      'spotId': 's',
                      'spotName': 'Осенняя встреча',
                      'endsAt': DateTime(
                        2026,
                        10,
                        1,
                        21,
                      ).millisecondsSinceEpoch,
                    },
                  ],
                },
              ),
            ),
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
      await Directory('build/achievement-previews').create(recursive: true);
      await File(
        'build/achievement-previews/weekly-live.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets(
    'admin targets load immediately, paginate and search while typing',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      Future<Map<String, dynamic>> request(
        String action, [
        Map<String, dynamic> extra = const {},
      ]) async {
        if (action != 'admin_reward_targets') return {'items': []};
        calls.add(extra);
        if (extra['search'] == 'Riga')
          return {
            'items': [
              {'id': 'riga', 'name': 'Riga spot'},
            ],
          };
        final offset = extra['offset'] as int;
        return {
          'items': List.generate(
            5,
            (i) => {'id': '${i + offset}', 'name': 'Spot ${i + offset}'},
          ),
          'nextOffset': offset == 0 ? 5 : null,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: AdminRewardsScreen(language: 'en', request: request),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add reward'));
      await tester.pumpAndSettle();
      expect(calls.single['search'], '');
      expect(find.text('Spot 0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Show more'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(calls.last['offset'], 5);
      await tester.scrollUntilVisible(
        find.text('Spot 9'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Spot 9'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Search by name'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        'Riga',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(calls.last, {'search': 'Riga', 'offset': 0});
      expect(find.text('Riga spot'), findsOneWidget);
      expect(find.text('Spot 0'), findsNothing);
    },
  );

  testWidgets('admin can select target and submit a dated fixed XP reward', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    Future<Map<String, dynamic>> request(
      String action, [
      Map<String, dynamic> extra = const {},
    ]) async {
      if (action == 'admin_reward_targets')
        return {
          'items': [
            {'id': 'spot-id', 'name': 'Meet place', 'event': true},
          ],
        };
      if (action == 'admin_reward_create') {
        saved = extra;
        return {'id': extra['id']};
      }
      return {'items': []};
    }

    await tester.pumpWidget(
      MaterialApp(
        home: AdminRewardsScreen(language: 'en', request: request),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add reward'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Attend our meet');
    await tester.enterText(find.byType(TextFormField).at(1), '250');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meet place'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create reward'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Create reward'));
    await tester.pumpAndSettle();
    expect(saved?['spotId'], 'spot-id');
    expect(saved?['xp'], 250);
    expect(saved?['endsAt'], greaterThan(saved!['startsAt'] as int));
    expect(find.text('Bonus tasks from admins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets(
      'active weekly tasks show confirmed pending and custom states in $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic> item(String status, int xp) => {
          'title': {
            'en': 'Visit a spot',
            'ru': 'Посетить спот',
            'lv': 'Apmeklēt vietu',
          },
          'xp': xp,
          'target': 2,
          'progress': 1,
          'status': status,
        };
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WeeklyRewardsSection(
                  language: language,
                  onOpenSpot: (id) => opened = id,
                  weekly: {
                    'status': 'active',
                    'totalXp': 600,
                    'consumedXp': 3000,
                    'limit': 3000,
                    'pendingXp': 250,
                    'items': [
                      item('active', 150),
                      item('confirmed', 200),
                      item('pending', 250),
                    ],
                    'adminItems': [
                      {
                        ...item('active', 100),
                        'spotId': 's',
                        'spotName': 'Meet place',
                        'endsAt': DateTime.now()
                            .add(const Duration(days: 7))
                            .millisecondsSinceEpoch,
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsNothing);
        await tester.scrollUntilVisible(find.byIcon(Icons.place_outlined), 150);
        await tester.tap(find.byIcon(Icons.place_outlined));
        expect(opened, 's');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
