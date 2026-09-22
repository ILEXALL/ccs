import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;

String spotCountryFromCityCountry(String value) {
  final parts = value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? '' : parts.last;
}

String _normalizedCountryName(String value) => value.trim().toLowerCase();

// Country values can be written by geocoders in the device language. Keeping
// all three app-language names behind one ISO identity prevents Latvia,
// Латвия and Latvija (for example) from appearing as separate filters.
const Map<String, List<String>> countryNamesByIso = <String, List<String>>{
  'AL': ['Albania', 'Албания', 'Albānija'],
  'AM': ['Armenia', 'Армения', 'Armēnija'],
  'AU': ['Australia', 'Австралия', 'Austrālija'],
  'AT': ['Austria', 'Австрия', 'Austrija'],
  'AZ': ['Azerbaijan', 'Азербайджан', 'Azerbaidžāna'],
  'BY': ['Belarus', 'Беларусь', 'Baltkrievija'],
  'BE': ['Belgium', 'Бельгия', 'Beļģija'],
  'BA': [
    'Bosnia and Herzegovina',
    'Босния и Герцеговина',
    'Bosnija un Hercegovina',
  ],
  'BR': ['Brazil', 'Бразилия', 'Brazīlija'],
  'BG': ['Bulgaria', 'Болгария', 'Bulgārija'],
  'CA': ['Canada', 'Канада', 'Kanāda'],
  'CN': ['China', 'Китай', 'Ķīna'],
  'HR': ['Croatia', 'Хорватия', 'Horvātija'],
  'CY': ['Cyprus', 'Кипр', 'Kipra'],
  'CZ': ['Czechia', 'Чехия', 'Čehija'],
  'DK': ['Denmark', 'Дания', 'Dānija'],
  'EE': ['Estonia', 'Эстония', 'Igaunija'],
  'FI': ['Finland', 'Финляндия', 'Somija'],
  'FR': ['France', 'Франция', 'Francija'],
  'GE': ['Georgia', 'Грузия', 'Gruzija'],
  'DE': ['Germany', 'Германия', 'Vācija'],
  'GR': ['Greece', 'Греция', 'Grieķija'],
  'HU': ['Hungary', 'Венгрия', 'Ungārija'],
  'IS': ['Iceland', 'Исландия', 'Islande'],
  'IN': ['India', 'Индия', 'Indija'],
  'IE': ['Ireland', 'Ирландия', 'Īrija'],
  'IT': ['Italy', 'Италия', 'Itālija'],
  'JP': ['Japan', 'Япония', 'Japāna'],
  'LV': ['Latvia', 'Латвия', 'Latvija'],
  'LT': ['Lithuania', 'Литва', 'Lietuva'],
  'LU': ['Luxembourg', 'Люксембург', 'Luksemburga'],
  'MT': ['Malta', 'Мальта', 'Malta'],
  'MX': ['Mexico', 'Мексика', 'Meksika'],
  'MD': ['Moldova', 'Молдова', 'Moldova'],
  'ME': ['Montenegro', 'Черногория', 'Melnkalne'],
  'NL': ['Netherlands', 'Нидерланды', 'Nīderlande'],
  'NZ': ['New Zealand', 'Новая Зеландия', 'Jaunzēlande'],
  'MK': ['North Macedonia', 'Северная Македония', 'Ziemeļmaķedonija'],
  'NO': ['Norway', 'Норвегия', 'Norvēģija'],
  'PL': ['Poland', 'Польша', 'Polija'],
  'PT': ['Portugal', 'Португалия', 'Portugāle'],
  'RO': ['Romania', 'Румыния', 'Rumānija'],
  'RU': ['Russia', 'Россия', 'Krievija'],
  'RS': ['Serbia', 'Сербия', 'Serbija'],
  'SK': ['Slovakia', 'Словакия', 'Slovākija'],
  'SI': ['Slovenia', 'Словения', 'Slovēnija'],
  'KR': ['South Korea', 'Южная Корея', 'Dienvidkoreja'],
  'ES': ['Spain', 'Испания', 'Spānija'],
  'SE': ['Sweden', 'Швеция', 'Zviedrija'],
  'CH': ['Switzerland', 'Швейцария', 'Šveice'],
  'TR': ['Turkey', 'Турция', 'Turcija'],
  'UA': ['Ukraine', 'Украина', 'Ukraina'],
  'AE': [
    'United Arab Emirates',
    'Объединённые Арабские Эмираты',
    'Apvienotie Arābu Emirāti',
  ],
  'GB': ['United Kingdom', 'Великобритания', 'Apvienotā Karaliste'],
  'US': ['United States', 'США', 'Amerikas Savienotās Valstis'],
};

final Map<String, String> _countryAliasesToIso = () {
  final aliases = <String, String>{};
  for (final entry in countryNamesByIso.entries) {
    aliases[_normalizedCountryName(entry.key)] = entry.key;
    for (final name in entry.value) {
      aliases[_normalizedCountryName(name)] = entry.key;
    }
  }
  aliases.addAll(const <String, String>{
    'czech republic': 'CZ',
    'чешская республика': 'CZ',
    'čehijas republika': 'CZ',
    'uk': 'GB',
    'great britain': 'GB',
    'россия': 'RU',
    'usa': 'US',
    'соединенные штаты': 'US',
    'соединённые штаты': 'US',
    'asv': 'US',
    'uae': 'AE',
    'оаэ': 'AE',
    'aae': 'AE',
  });
  return aliases;
}();

String? countryIsoCode(String value) =>
    _countryAliasesToIso[_normalizedCountryName(value)];

String spotCountryKey(String value) =>
    countryIsoCode(value) ?? _normalizedCountryName(value);

String canonicalSpotCountryName(String value) {
  final isoCode = countryIsoCode(value);
  return isoCode == null ? value.trim() : countryNamesByIso[isoCode]!.first;
}

String localizedCountryName(String value, {AppLanguage? language}) {
  final isoCode = countryIsoCode(value);
  final names = isoCode == null ? null : countryNamesByIso[isoCode];
  if (names == null) {
    return value.trim();
  }
  return names[switch (language ?? appUiPreferences.language) {
    AppLanguage.en => 0,
    AppLanguage.ru => 1,
    AppLanguage.lv => 2,
  }];
}

List<String> allSupportedCountryNames() {
  final countries = countryNamesByIso.values
      .map((names) => names.first)
      .toList(growable: false);
  countries.sort(
    (first, second) => localizedCountryName(
      first,
    ).toLowerCase().compareTo(localizedCountryName(second).toLowerCase()),
  );
  return countries;
}

List<String> countryRestrictionKeys(Set<String> countryCodes) {
  final keys = <String>{};
  for (final code in countryCodes) {
    final cleanCode = code.trim().toUpperCase();
    final names = countryNamesByIso[cleanCode];
    if (names == null) continue;
    keys.add(cleanCode.toLowerCase());
    keys.addAll(names.map(_normalizedCountryName));
    if (cleanCode == 'GB') keys.addAll(const ['uk', 'great britain']);
    if (cleanCode == 'US') keys.addAll(const ['usa', 'сша', 'asv']);
    if (cleanCode == 'AE') keys.addAll(const ['uae', 'оаэ', 'aae']);
    if (cleanCode == 'CZ') {
      keys.addAll(const [
        'czech republic',
        'чешская республика',
        'čehijas republika',
      ]);
    }
  }
  final sorted = keys.toList(growable: false)..sort();
  return sorted;
}

String countryFlagEmoji(String country) {
  final isoCode = countryIsoCode(country);
  if (isoCode == null || isoCode.length != 2) {
    return '🌍';
  }
  return String.fromCharCodes(isoCode.codeUnits.map((unit) => unit + 127397));
}
