import 'package:ccs_app/core/localization/app_language.dart'
    as app
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' as app show trText;
import 'package:ccs_app/features/progression/data/leaderboard.dart'
    as app
    show XpLeaderboardPage, XpLeaderboardPeriod, xpLeaderboardPeriodLabel;
import 'package:ccs_app/features/progression/models/leaderboard_entry.dart'
    as app
    show XpLeaderboardEntry;
import 'package:ccs_app/features/progression/screens/leaderboard_screen.dart'
    as app
    show XpLeaderboardScreen;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'ranking translates immediately without refetching or losing rows',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previous = app.appUiPreferences.language;
      addTearDown(() => app.appUiPreferences.language = previous);
      app.appUiPreferences.language = app.AppLanguage.ru;
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: app.XpLeaderboardScreen(
            embedded: true,
            loadPage: ({required period, required search, cursor}) async {
              loads++;
              return app.XpLeaderboardPage(
                entries: [
                  app.XpLeaderboardEntry.fromJson({
                    'userId': 'driver',
                    'username': 'test_driver',
                    'rank': 1,
                    'xpTotal': 6400,
                  }, fallbackRank: 1),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final language in [
        app.AppLanguage.en,
        app.AppLanguage.lv,
        app.AppLanguage.ru,
        app.AppLanguage.en,
      ]) {
        await app.appUiPreferences.setLanguage(language);
        await tester.pumpAndSettle();
        final input = tester.widget<TextField>(
          find.byKey(const ValueKey('ranking-search')),
        );
        expect(
          input.decoration!.hintText,
          language == app.AppLanguage.en
              ? 'Search by nickname'
              : language == app.AppLanguage.ru
              ? 'Поиск по нику'
              : 'Meklēt pēc lietotājvārda',
        );
        expect(
          find.text(
            app.xpLeaderboardPeriodLabel(app.XpLeaderboardPeriod.allTime),
          ),
          findsOneWidget,
        );
        expect(
          find.text(app.xpLeaderboardPeriodLabel(app.XpLeaderboardPeriod.week)),
          findsOneWidget,
        );
        for (final label in ['Level', 'Total XP', 'Weekly XP']) {
          expect(find.text(app.trText(label)), findsWidgets);
        }
        expect(loads, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
