import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

const savedSpotsKey = 'saved_spot_ids_v1';

Set<String> savedSpotIds = {};

Future<void> loadSavedSpotsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    savedSpotIds = (prefs.getStringList(savedSpotsKey) ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    restoreSavedSpotsFromFirebaseCache();
  } catch (_) {}
}

Future<void> saveSavedSpotIds() async {
  try {
    savedSpotIds = savedSpots.value
        .map((spot) => spot.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(savedSpotsKey, savedSpotIds.toList());
  } catch (_) {}
}

void restoreSavedSpotsFromFirebaseCache() {
  if (savedSpotIds.isEmpty) {
    if (savedSpots.value.isNotEmpty) {
      savedSpots.value = [];
    }
    return;
  }

  final availableById = <String, CarSpot>{
    for (final spot in reviewSpots.value)
      if (spot.id.trim().isNotEmpty) spot.id.trim(): spot,
  };
  final restored = savedSpotIds
      .map((id) => availableById[id])
      .whereType<CarSpot>()
      .toList();
  final unchanged =
      restored.length == savedSpots.value.length &&
      restored.every(
        (spot) => savedSpots.value.any((saved) => isSameSpot(saved, spot)),
      );

  if (!unchanged) {
    savedSpots.value = restored;
  }
}
