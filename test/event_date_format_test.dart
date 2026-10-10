import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/core/time/trusted_clock.dart';
import 'package:ccs_app/core/localization/app_language.dart';
import 'package:ccs_app/features/events/models/event_date_format.dart';

void main() {
  final original = appUiPreferences.language;
  tearDown(() {
    trustedClock.setSampleForTesting(null);
    appUiPreferences.language = original;
  });
  test(
    'relative event dates use calendar days and localize across month boundary',
    () {
      trustedClock.setSampleForTesting(
        DateTime(2026, 10, 31, 23, 30).millisecondsSinceEpoch,
      );
      final labels = {
        AppLanguage.en: ['Today', 'Tomorrow'],
        AppLanguage.ru: ['Сегодня', 'Завтра'],
        AppLanguage.lv: ['Šodien', 'Rīt'],
      };
      for (final entry in labels.entries) {
        appUiPreferences.language = entry.key;
        expect(formatEventDate(DateTime(2026, 10, 31, 1)), entry.value[0]);
        expect(formatEventDate(DateTime(2026, 11, 1, 23)), entry.value[1]);
        expect(formatEventDate(DateTime(2026, 11, 2)), startsWith('2. '));
      }
    },
  );
  test(
    'without trusted time retain explicit date rather than trust phone clock',
    () {
      appUiPreferences.language = AppLanguage.en;
      trustedClock.setSampleForTesting(null);
      expect(formatEventDate(DateTime(2026, 10, 10)), '10. OCT');
    },
  );
}
