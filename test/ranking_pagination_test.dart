import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'support/preview_font.dart';
import 'dart:async';
import 'package:ccs_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

app.XpLeaderboardEntry entry(int index, {String prefix = 'driver'}) =>
    app.XpLeaderboardEntry.fromJson({
      'userId': '$prefix-$index',
      'username': '${prefix}_$index',
      'rank': index + 1,
      'xpTotal': 1000 - index,
    }, fallbackRank: index + 1);
app.XpLeaderboardPage page(
  int start, {
  bool more = false,
  String prefix = 'driver',
}) => app.XpLeaderboardPage(
  entries: List.generate(10, (i) => entry(start + i, prefix: prefix)),
  nextCursor: more ? {'offset': start + 10} : null,
);
Future<void> mount(
  WidgetTester tester,
  app.XpLeaderboardPageLoader loader,
) async {
  app.appUiPreferences.language = app.AppLanguage.en;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: app.XpLeaderboardScreen(embedded: true, loadPage: loader),
    ),
  );
}

Future<void> tapBottom(WidgetTester tester, String key) async {
  final list = find.byKey(const ValueKey('ranking-list'));
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    500,
    scrollable: scrollable,
  );
  await tester.tap(find.byKey(ValueKey(key)));
}

void main() {
  for (final language in app.AppLanguage.values) {
    for (final width in [320.0, 430.0]) {
      testWidgets(
        'ranking controls ${language.name} at $width with enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          app.appUiPreferences.language = language;
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: key,
                child: app.XpLeaderboardScreen(
                  embedded: true,
                  loadPage:
                      ({required period, required search, cursor}) async =>
                          page(0, more: true),
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
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/ranking-previews');
            await directory.create(recursive: true);
            await File(
              '${directory.path}/${language.name}-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        },
      );
    }
  }

  testWidgets('loads one page, appends ten on demand, and stops at the end', (
    tester,
  ) async {
    final cursors = <Map<String, dynamic>?>[];
    await mount(tester, ({required period, required search, cursor}) async {
      cursors.add(cursor);
      return page(cursor == null ? 0 : 10, more: cursor == null);
    });
    await tester.pumpAndSettle();
    expect(cursors.length, 1);
    await tapBottom(tester, 'ranking-load-more');
    await tester.pumpAndSettle();
    expect(cursors.length, 2);
    expect(cursors.last, {'offset': 10});
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('ranking-list')),
    );
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    expect(children.whereType<app.XpLeaderboardTile>().length, 20);
    expect(find.byKey(const ValueKey('ranking-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed next page preserves rows and retries the same cursor', (
    tester,
  ) async {
    var fail = true;
    final cursors = <Map<String, dynamic>?>[];
    await mount(tester, ({required period, required search, cursor}) async {
      cursors.add(cursor);
      if (cursor != null && fail) throw StateError('offline');
      return page(cursor == null ? 0 : 10, more: cursor == null);
    });
    await tester.pumpAndSettle();
    await tapBottom(tester, 'ranking-load-more');
    await tester.pumpAndSettle();
    var list = tester.widget<ListView>(
      find.byKey(const ValueKey('ranking-list')),
    );
    expect(
      (list.childrenDelegate as SliverChildListDelegate).children
          .whereType<app.XpLeaderboardTile>()
          .length,
      10,
    );
    fail = false;
    await tapBottom(tester, 'ranking-retry');
    await tester.pumpAndSettle();
    expect(cursors[1], cursors[2]);
    list = tester.widget<ListView>(find.byKey(const ValueKey('ranking-list')));
    expect(
      (list.childrenDelegate as SliverChildListDelegate).children
          .whereType<app.XpLeaderboardTile>()
          .length,
      20,
    );
  });
  testWidgets(
    'search debounces, resets pagination and ignores late responses',
    (tester) async {
      final initial = Completer<app.XpLeaderboardPage>();
      final calls = <String>[];
      await mount(tester, ({required period, required search, cursor}) {
        calls.add(search);
        expect(cursor, isNull);
        if (calls.length == 1) return initial.future;
        return Future.value(page(0, prefix: search.isEmpty ? 'reset' : search));
      });
      await tester.pump();
      final field = find.byKey(const ValueKey('ranking-search'));
      await tester.enterText(field, '@AL');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(field, '@ALEX');
      initial.complete(page(0, prefix: 'stale'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, ['']);
      expect(find.byKey(const ValueKey('ranking-user-stale-0')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(calls, ['', 'alex']);
      expect(find.byKey(const ValueKey('ranking-user-alex-0')), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls, ['', 'alex', '']);
      expect(
        find.byKey(const ValueKey('ranking-user-reset-0')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'switching periods resets cursor and ignores previous period results',
    (tester) async {
      final old = Completer<app.XpLeaderboardPage>();
      await mount(tester, ({required period, required search, cursor}) {
        expect(cursor, isNull);
        return period == app.XpLeaderboardPeriod.allTime
            ? old.future
            : Future.value(page(0, prefix: 'weekly'));
      });
      await tester.pump();
      final selector = tester.widget<app.XpLeaderboardPeriodSelector>(
        find.byType(app.XpLeaderboardPeriodSelector),
      );
      selector.onChanged(app.XpLeaderboardPeriod.week);
      await tester.pumpAndSettle();
      old.complete(page(0, prefix: 'stale'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ranking-user-weekly-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ranking-user-stale-0')), findsNothing);
    },
  );
  testWidgets('empty search keeps controls and can be cleared', (tester) async {
    await mount(
      tester,
      ({required period, required search, cursor}) async =>
          const app.XpLeaderboardPage(entries: []),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ranking-search')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No matching users in this ranking.'), findsOneWidget);
    expect(find.byType(app.XpLeaderboardPeriodSelector), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });
  testWidgets('expired cursor offers a fresh first page', (tester) async {
    final cursors = <Map<String, dynamic>?>[];
    await mount(tester, ({required period, required search, cursor}) async {
      cursors.add(cursor);
      if (cursor != null) throw app.XpLeaderboardPageExpired();
      return page(0, more: true);
    });
    await tester.pumpAndSettle();
    await tapBottom(tester, 'ranking-load-more');
    await tester.pumpAndSettle();
    await tapBottom(tester, 'ranking-retry');
    await tester.pumpAndSettle();
    expect(cursors.length, 3);
    expect(cursors.last, isNull);
  });
}
