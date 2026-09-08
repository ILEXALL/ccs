import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['en', 'ru', 'lv']) {
    testWidgets('achievement screen $language fits phone and records preview', (tester) async {
      tester.view.reset();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.runAsync(() async {
        final font = FontLoader('PreviewFont');
        font.addFont(File('C:/Windows/Fonts/arial.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final items = [
        for (final category in ['spots', 'groups', 'reports', 'moderator', 'tourist'])
          {'id': category, 'category': category, 'title': {'en': category, 'ru': {'spots':'Споты', 'groups':'Владелец группы', 'reports':'Подтверждённые репорты', 'moderator':'Стаж модератора', 'tourist':'Латвия'}[category], 'lv': {'spots':'Vietas', 'groups':'Grupas īpašnieks', 'reports':'Apstiprināti ziņojumi', 'moderator':'Moderatora stāžs', 'tourist':'Latvija'}[category]},
            'xp': 100, 'threshold': 10, 'tier': 1, 'unit': category == 'tourist' ? 'country' : 'count',
            'progress': 0, 'available': category == 'spots', 'status': 'locked',
            if (category == 'tourist') 'asset': 'assets/achievements/latvia.png'},
      ];
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'PreviewFont')), home: RepaintBoundary(key: key,
        child: AchievementsScreen(language: language, load: () async => {'enabled': false, 'items': items}))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/achievement-previews');
      await dir.create(recursive: true);
      await File('${dir.path}/$language.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      });
    });
  }
}
