import 'support/preview_font.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ccs_app/achievements_screen.dart';
import 'package:ccs_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> fonts(WidgetTester tester) => tester.runAsync(() async {
  final file = File(previewFontPath);
  if (await file.exists()) {
    final font = FontLoader('PreviewFont');
    font.addFont(file.readAsBytes().then(ByteData.sublistView));
    await font.load();
  }
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
});

Future<void> capture(WidgetTester tester, GlobalKey key, String name) => tester.runAsync(() async {
  final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('build/achievement-previews');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
});

void main() {
  testWidgets('all seven active categories render five earned tiers including purple', (tester) async {
    tester.view.physicalSize = const Size(660, 1040); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await fonts(tester); final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'PreviewFont')),
      home: RepaintBoundary(key: key, child: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text('CCS · Достижения', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        for (final category in ['spots', 'visits', 'meets', 'topics', 'tenure', 'moderator', 'groups'])
          Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
            SizedBox(width: 125, child: Text(achievementCategoryLabel(category, 'ru'))),
            for (var tier = 1; tier <= 5; tier++) Expanded(child: Center(child: AchievementBadge(
              item: {'category':category, 'tier':tier, 'threshold': tier, 'status': 'confirmed'}))),
          ])),
      ]))))));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/ccs_logo.png'), key.currentContext!));
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    expect(find.byType(AchievementBadge), findsNWidgets(35));
    expect(tester.widgetList<AchievementBadge>(find.byType(AchievementBadge))
      .where((badge) => badge.item['tier'] == 5).length, 7);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(Image), findsNWidgets(5));
    expect(find.byIcon(Icons.diamond_outlined), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect((image.image as AssetImage).assetName, 'assets/ccs_logo.png');
    }
    await capture(tester, key, 'emblems-five-tiers');
  });
  testWidgets('public achievement list is read-only and has an empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AchievementsScreen(language: 'en',
      load: () async => {'enabled':true, 'public':true, 'items':[]})));
    await tester.pumpAndSettle();
    expect(find.text('No unlocked achievements yet'), findsOneWidget);
    expect(find.text('Show on profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final language in app.AppLanguage.values) {
    for (final width in [320.0, 430.0]) {
      for (final period in app.XpLeaderboardPeriod.values) {
        testWidgets('ranking ${language.name} $width ${period.name} keeps all three metrics aligned', (tester) async {
          tester.view.physicalSize = Size(width, 780); tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
          app.appUiPreferences.language = language;
          await fonts(tester); final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'PreviewFont')),
            home: RepaintBoundary(key: key, child: Scaffold(body: ListView(padding: const EdgeInsets.all(14), children: [
              for (final rank in [1, 2, 3, 10, 11]) app.XpLeaderboardTile(period: period,
                entry: app.XpLeaderboardEntry(rank:rank, userId:'user-$rank', username:'Driver_$rank', name:'Driver_$rank',
                  photoUrl:'', avatarPath:'', city:'Riga', country:'Latvia', verified:true, xpTotal:245025, weeklyXp:3000, level:100)),
            ])))));
          await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
          final level = tester.getRect(find.text(app.trText('Level')).first);
          final total = tester.getRect(find.text(app.trText('Total XP')).first);
          final weekly = tester.getRect(find.text(app.trText('Weekly XP')).first);
          expect(level.top, total.top); expect(total.top, weekly.top);
          expect(weekly.right, lessThanOrEqualTo(width));
          if (language == app.AppLanguage.ru) await capture(tester, key, 'ranking-${period.name}-${width.toInt()}');
        });
      }
    }
  }
}
