import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/location/coordinates.dart' show isValidLatLng;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots, moderatorCountryCodesFromFirebase;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show firebaseSpotCacheBySource;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/shared/models/countries.dart'
    show
        allSupportedCountryNames,
        canonicalSpotCountryName,
        countryIsoCode,
        localizedCountryName,
        spotCountryFromCityCountry,
        spotCountryKey;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase;

const spotCategoryFiltersKey = 'spot_category_filters';

const spotCountryFiltersKeyPrefix = 'spot_country_filters_v1';

final spotCategoryFilters = ValueNotifier<Set<String>>({
  ...spotCategoryOptions,
});

final spotCountryFilters = ValueNotifier<Set<String>>(<String>{});

String localizedSpotFilterSummary({
  required int selectedCategories,
  required int totalCategories,
  required int selectedCountries,
}) {
  return switch (appUiPreferences.language) {
    AppLanguage.en =>
      'Categories: $selectedCategories/$totalCategories • Countries: $selectedCountries',
    AppLanguage.ru =>
      'Категории: $selectedCategories/$totalCategories • Страны: $selectedCountries',
    AppLanguage.lv =>
      'Kategorijas: $selectedCategories/$totalCategories • Valstis: $selectedCountries',
  };
}

Set<String> cleanSpotCountries(Iterable<String> countries) {
  final byKey = <String, String>{};
  for (final country in countries) {
    final cleanCountry = canonicalSpotCountryName(country);
    if (!isSelectableSpotCountry(cleanCountry)) {
      continue;
    }
    final key = spotCountryKey(cleanCountry);
    if (key.isNotEmpty) {
      byKey[key] = cleanCountry;
    }
  }
  return byKey.values.toSet();
}

bool isSelectableSpotCountry(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll('…', '...')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty || normalized == 'unknown location') {
    return false;
  }

  return !normalized.startsWith('finding address') &&
      !normalized.startsWith('detecting city/country') &&
      !normalized.startsWith('getting current location') &&
      !normalized.startsWith('choose location to detect city/country');
}

Set<String> spotCountryFiltersFromUserData(Map<String, dynamic> data) {
  final rawFilters = data['spotCountryFilters'];
  final selected = rawFilters is Iterable
      ? cleanSpotCountries(rawFilters.whereType<String>())
      : <String>{};
  if (selected.isNotEmpty) {
    return selected;
  }

  final userCountry = stringFromFirebase(data['country'], '').trim();
  return userCountry.isEmpty
      ? <String>{}
      : cleanSpotCountries(<String>{userCountry});
}

String spotFilterCountry(CarSpot spot) {
  // The stored ISO code is stable across device/geocoder languages.
  final code = spot.effectiveCountryCode;
  return code.isNotEmpty
      ? canonicalSpotCountryName(code)
      : spotCountryFromCityCountry(spot.cityCountry);
}

bool spotMatchesSelectedCountries(CarSpot spot) {
  final selectedKeys = spotCountryFilters.value
      .map(spotCountryKey)
      .where((key) => key.isNotEmpty)
      .toSet();
  if (selectedKeys.isEmpty) {
    return false;
  }
  return selectedKeys.contains(spotCountryKey(spotFilterCountry(spot)));
}

bool userDataAllowsSpotCountry(Map<String, dynamic> data, String spotCountry) {
  final countryKey = spotCountryKey(spotCountry);
  if (countryKey.isEmpty) {
    return true;
  }
  if (roleFromFirebase(data['role']) == UserRole.moderator) {
    return moderatorCountryCodesFromFirebase(
      data['moderatorCountryCodes'],
    ).contains(countryKey.toUpperCase());
  }
  final selected = spotCountryFiltersFromUserData(data);
  if (selected.isEmpty) {
    // Preserve delivery for legacy/incomplete profiles that have no country.
    return true;
  }
  return selected.map(spotCountryKey).contains(countryKey);
}

List<String> availableSpotCountries() {
  final countriesByKey = <String, String>{};

  void addCountry(String value) {
    final country = canonicalSpotCountryName(value);
    if (!isSelectableSpotCountry(country)) {
      return;
    }
    final key = spotCountryKey(country);
    if (key.isNotEmpty) {
      countriesByKey[key] = country;
    }
  }

  // The user's own country must remain selectable even before its first spot
  // is loaded, because it is the default for a new account.
  addCountry(currentUser.country);
  for (final spot in approvedPublicSpots()) {
    if (!spot.isExpired) {
      addCountry(spotFilterCountry(spot));
    }
  }

  final countries = countriesByKey.values.toList(growable: false);
  countries.sort(
    (first, second) => localizedCountryName(
      first,
    ).toLowerCase().compareTo(localizedCountryName(second).toLowerCase()),
  );
  return countries;
}

List<String> availableCommunityCountryCodes() {
  // Community countries are controlled by Regional restrictions, not the
  // Spots/Map country filter. Checked countries there are restricted and
  // therefore must not appear in the community country picker.
  final restrictedCodes = maintenanceModeConfig.value.bannedCountryCodes
      .map((code) => countryIsoCode(code) ?? code.trim().toUpperCase())
      .where((code) => code.isNotEmpty)
      .toSet();

  final countries = allSupportedCountryNames()
      .map(countryIsoCode)
      .whereType<String>()
      .where((code) => !restrictedCodes.contains(code))
      .toSet()
      .toList(growable: false);

  countries.sort(
    (a, b) => localizedCountryName(
      a,
    ).toLowerCase().compareTo(localizedCountryName(b).toLowerCase()),
  );
  return countries;
}

String spotCountryPreferenceKey(String uid) =>
    '${spotCountryFiltersKeyPrefix}_${uid.trim()}';

Future<void> saveSpotCountryFiltersPreference(
  String uid,
  Set<String> countries,
) async {
  if (uid.trim().isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      spotCountryPreferenceKey(uid),
      countries.toList()..sort(),
    );
  } catch (_) {}
}

Future<void> initializeSpotCountryFiltersForUser(AppUser user) async {
  final uid = user.uid.trim();
  if (uid.isEmpty) {
    spotCountryFilters.value = <String>{};
    return;
  }

  Set<String> localFilters = <String>{};
  try {
    final prefs = await SharedPreferences.getInstance();
    localFilters = cleanSpotCountries(
      prefs.getStringList(spotCountryPreferenceKey(uid)) ?? const <String>[],
    );
  } catch (_) {}

  Set<String> remoteFilters = <String>{};
  try {
    final snapshot = await usersCollection().doc(uid).debugGet();
    final data = snapshot.data();
    if (data != null && data['spotCountryFilters'] is Iterable) {
      remoteFilters = cleanSpotCountries(
        (data['spotCountryFilters'] as Iterable).whereType<String>(),
      );
    }
  } catch (_) {}

  final ownCountry = canonicalSpotCountryName(user.country);
  final selected = remoteFilters.isNotEmpty
      ? remoteFilters
      : localFilters.isNotEmpty
      ? localFilters
      : ownCountry.isEmpty
      ? <String>{}
      : cleanSpotCountries(<String>{ownCountry});
  spotCountryFilters.value = selected;
  await saveSpotCountryFiltersPreference(uid, selected);

  if (remoteFilters.isEmpty && selected.isNotEmpty) {
    try {
      await usersCollection().doc(uid).debugSet({
        'spotCountryFilters': selected.toList()..sort(),
        'spotCountryFiltersUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Could not initialize spot country filters: $error');
    }
  }
}

Future<void> updateSpotCountryFilters(Set<String> countries) async {
  final uid = currentUser.uid.trim();
  var selected = cleanSpotCountries(countries);
  if (selected.isEmpty && currentUser.country.trim().isNotEmpty) {
    selected = cleanSpotCountries(<String>{currentUser.country});
  }
  spotCountryFilters.value = selected;
  await saveSpotCountryFiltersPreference(uid, selected);
  if (uid.isEmpty) return;

  try {
    await usersCollection().doc(uid).debugSet({
      'spotCountryFilters': selected.toList()..sort(),
      'spotCountryFiltersUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error) {
    debugPrint('Could not save spot country filters: $error');
  }
}

Set<String> sanitizedSpotCategoryFilters(Iterable<String> categories) {
  final validCategories = spotCategoryOptions.toSet();
  final cleanCategories = categories
      .map((category) => category.trim())
      .where(validCategories.contains)
      .toSet();

  return cleanCategories;
}

Future<void> loadSpotCategoryFiltersPreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedCategories = prefs.getStringList(spotCategoryFiltersKey);

    if (savedCategories == null) {
      return;
    }

    spotCategoryFilters.value = sanitizedSpotCategoryFilters(savedCategories);
  } catch (_) {}
}

Future<void> saveSpotCategoryFiltersPreference(Set<String> categories) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      spotCategoryFiltersKey,
      categories.toList()..sort(),
    );
  } catch (_) {}
}

void updateSpotCategoryFilters(Set<String> categories) {
  final cleanCategories = sanitizedSpotCategoryFilters(categories);
  spotCategoryFilters.value = cleanCategories;
  unawaited(saveSpotCategoryFiltersPreference(cleanCategories));
}

List<CarSpot> approvedPublicSpots() {
  // Public Explore/Map must show only real Firebase spots.
  // Demo spots stay in code as backup data, but they should not reappear
  // after an admin deletes an approved Firebase spot.
  // Review/submission/local-immediate sources may have older snapshots with
  // client timestamps ahead of the server. They must not override the public
  // feed's status, country, or temporary schedule on just one device.
  return <String, CarSpot>{
        ...?firebaseSpotCacheBySource['approved'],
        ...?firebaseSpotCacheBySource['group spots'],
      }.values
      .where(
        (spot) =>
            canViewGroupSpot(spot) &&
            spot.status == SpotStatus.approved &&
            spot.isVisibleNow &&
            (!spot.verifiedOnly || currentUserCanUseVerifiedOnlySpots),
      )
      .toList();
}

// MarkerLayer culls off-screen markers. Do not drop eligible spots based on
// distance, density, or nearby events: those cuts make live spots disappear.
List<CarSpot> mapVisibleSpots(Iterable<CarSpot> spots) {
  final categories = spotCategoryFilters.value;
  if (categories.isEmpty || spotCountryFilters.value.isEmpty) return const [];
  return spots
      .where(
        (spot) =>
            spot.status == SpotStatus.approved &&
            spotMatchesSelectedCountries(spot) &&
            spot.categories.any(categories.contains) &&
            spot.isVisibleOnMapNow &&
            isValidLatLng(spot.coordinates),
      )
      .toList();
}

List<CarSpot> pendingReviewSpots() {
  return reviewSpots.value
      .where((spot) => spot.status == SpotStatus.pending)
      .toList();
}
