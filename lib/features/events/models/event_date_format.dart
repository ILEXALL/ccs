import 'package:ccs_app/core/time/trusted_clock.dart' show trustedClock;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;

String formatEventDate(DateTime date) {
  date = date.toLocal();
  final nowMillis = trustedClock.nowMillis;
  if (nowMillis != null) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMillis);
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return trText('Today');
    if (day == tomorrow) return trText('Tomorrow');
  }

  final months = switch (appUiPreferences.language) {
    AppLanguage.en => const [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ],
    AppLanguage.ru => const [
      'ЯНВ',
      'ФЕВ',
      'МАР',
      'АПР',
      'МАЙ',
      'ИЮН',
      'ИЮЛ',
      'АВГ',
      'СЕН',
      'ОКТ',
      'НОЯ',
      'ДЕК',
    ],
    AppLanguage.lv => const [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAI',
      'JŪN',
      'JŪL',
      'AUG',
      'SEP',
      'OKT',
      'NOV',
      'DEC',
    ],
  };
  return '${date.day}. ${months[date.month - 1]}';
}
