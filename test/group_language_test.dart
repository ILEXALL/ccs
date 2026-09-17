import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    app.appUiPreferences.language = app.AppLanguage.en;
  });

  test('group notifications translate without changing names', () {
    for (final language in [app.AppLanguage.ru, app.AppLanguage.lv]) {
      for (final text in [
        '@alex wants to join Night Drivers.',
        'Your request to join Night Drivers was accepted.',
        'Your request to join Night Drivers was rejected.',
      ]) {
        final translated = app.trText(text, language: language);
        expect(translated, isNot(text));
        expect(translated, contains('Night Drivers'));
      }
    }
  });

  testWidgets('request screen follows language changes without reloading', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.GroupJoinRequestsScreen(
          chatId: 'group',
          applicantLoader: (_) async => null,
          requestAction: (_) async {
            loads++;
            return {
              'requests': [
                {'uid': 'alex', 'username': 'alex'},
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final language in [
      app.AppLanguage.ru,
      app.AppLanguage.lv,
      app.AppLanguage.en,
    ]) {
      await app.appUiPreferences.setLanguage(language);
      await tester.pumpAndSettle();
      for (final text in [
        'Join requests',
        'View profile',
        'Accept',
        'Reject',
        'Wants to join your group',
      ]) {
        expect(find.text(app.trText(text)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
    expect(loads, 1);
  });
}
