import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection, currentUserHomeCountryCode;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;

String profileAuthorCountryCode(
  Map<String, dynamic>? profile,
  String fallback,
) => profile == null
    ? fallback
    : countryIsoCode(stringFromFirebase(profile['country'], '')) ?? '';

String get chooseProfileCountryMessage => communityText(
  en: 'Choose your country in Profile → Edit Profile before posting.',
  ru: 'Перед публикацией выберите страну: Профиль → Редактировать профиль.',
  lv: 'Pirms publicēšanas izvēlieties valsti: Profils → Rediģēt profilu.',
);

bool ensureCommunityProfileCountry(BuildContext context) {
  if (currentUserHomeCountryCode().isNotEmpty) return true;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: CcsText(chooseProfileCountryMessage)));
  return false;
}

bool get isViewingHomeCommunity =>
    communityCountrySelection.value == currentUserHomeCountryCode();

String communityContentCountryCode(Map<String, dynamic> data) {
  final explicitCode = stringFromFirebase(data['countryCode'], '').trim();
  final explicitCountry = stringFromFirebase(data['country'], '').trim();
  return countryIsoCode(explicitCode) ??
      countryIsoCode(explicitCountry) ??
      // Global/Forum documents created before regional communities belong to
      // the original Latvian community.
      'LV';
}

String communityAuthorCountryCode(Map<String, dynamic> data) {
  return countryIsoCode(stringFromFirebase(data['authorCountryCode'], '')) ??
      countryIsoCode(stringFromFirebase(data['country'], '')) ??
      '';
}

String communityText({
  required String en,
  required String ru,
  required String lv,
}) => switch (appUiPreferences.language) {
  AppLanguage.en => en,
  AppLanguage.ru => ru,
  AppLanguage.lv => lv,
};
