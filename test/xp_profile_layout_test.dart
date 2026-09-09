import 'dart:io';
import 'dart:ui' as ui;
import 'package:ccs_app/main.dart' as app;
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared app bars no longer include Top 100', () {
    expect(
      app.ccsAppBarActions().whereType<app.CcsXpLeaderboardAction>(),
      isEmpty,
    );
  });
  for (final width in [320.0, 430.0]) {
    for (final language in app.AppLanguage.values) {
      testWidgets('XP profile layout ${language.name} at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        app.appUiPreferences.language = language;
        final key = GlobalKey();
        await tester.runAsync(() async {
          final font = FontLoader('PreviewFont');
          font.addFont(
            File(
              'C:/Windows/Fonts/arial.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
          await font.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
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
                body: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: app.CcsXpLeaderboardAction(),
                      ),
                      const SizedBox(height: 24),
                      app.XpSummaryContent(
                        stats: app.XpUserStats(
                          userId: app.currentUser.uid,
                          xpTotal: 360,
                          level: 4,
                          weeklyXp: 360,
                          weeklyXpWeek: '2026-09-07',
                          xpBlocked: false,
                          xpLastTransactionId: '',
                        ),
                        loading: false,
                        unavailable: false,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(XpProfileActions), findsOneWidget);
        expect(find.text('This week XP'), findsNothing);
        expect(find.text('Total XP'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/achievement-previews');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/profile-${language.name}-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
