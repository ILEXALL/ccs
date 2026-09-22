import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'support/preview_font.dart';
import 'package:ccs_app/features/progression/screens/xp_rewards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reward(
  String id, {
  int completed = 0,
  int pending = 0,
  bool repeatable = false,
}) => {
  'id': id,
  'title': {'en': id, 'ru': id, 'lv': id},
  'category': repeatable ? 'spot' : 'profile',
  'xp': 50,
  'completed': completed,
  'earnedXp': completed * 50,
  'pending': pending,
  'repeatable': repeatable,
};
void main() {
  testWidgets('render rewards overview', (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
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
          child: XpRewardsScreen(
            language: 'ru',
            load: () async => {
              'items': [
                reward('Добавить фото профиля', completed: 1),
                reward('Написать о себе (от 20 символов)'),
                reward('Указать город', pending: 1),
                reward(
                  'Опубликовать одобренный спот',
                  completed: 2,
                  repeatable: true,
                ),
              ],
            },
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
        'build/achievement-previews/rewards-overview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets('reward states and filters fit narrow screen in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: XpRewardsScreen(
            language: language,
            load: () async => {
              'items': [
                reward('unfinished'),
                reward('received', completed: 1),
                reward('waiting', pending: 1),
                reward(
                  'repeatable',
                  completed: 3,
                  pending: 1,
                  repeatable: true,
                ),
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsWidgets);
      await tester.tap(find.byType(ChoiceChip).at(3));
      await tester.pumpAndSettle();
      expect(find.text('unfinished'), findsNothing);
      expect(find.text('received'), findsNothing);
      expect(find.text('waiting'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('repeatable'), 150);
      expect(find.text('repeatable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('finished first steps start collapsed and can be expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: XpRewardsScreen(
          language: 'en',
          load: () async => {
            'items': [reward('finished', completed: 1)],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('finished'), findsNothing);
    await tester.tap(find.text('First steps'));
    await tester.pumpAndSettle();
    expect(find.text('finished'), findsOneWidget);
  });
}
