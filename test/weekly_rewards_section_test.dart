import 'package:ccs_app/achievements_screen.dart';
import 'package:ccs_app/weekly_rewards_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

void main() {
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets('weekly preview $language fits a narrow screen without claim controls', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('PreviewFont');
        font.addFont(File('C:/Windows/Fonts/arial.ttf').readAsBytes().then(ByteData.sublistView));
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'PreviewFont')),
        home: RepaintBoundary(key: key, child: XpRewardsScreen(language: language, load: () async => {
        'weekly': {'status': 'preview', 'items': [for (var i = 0; i < 3; i++) {
          'difficulty': i, 'xp': [75, 100, 125][i],
          'title': {'en': 'Visit different spots on three days', 'ru': 'Посетить разные споты в три разных дня',
            'lv': 'Apmeklēt dažādas vietas trijās dienās'},
        }]},
        'items': [],
      }))));
      await tester.pumpAndSettle();
      expect(find.byType(WeeklyRewardsSection), findsOneWidget);
      for (final xp in [75, 100, 125]) expect(find.text('+$xp XP'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      if (language == 'ru') await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/achievement-previews').create(recursive: true);
        await File('build/achievement-previews/weekly-rewards.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
