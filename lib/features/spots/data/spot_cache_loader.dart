import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show firestoreDebugTracker;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show firebaseSpotCacheBySource, spotSyncIsCurrent;
import 'package:ccs_app/features/spots/data/spot_feed_projection.dart'
    show publishFirebaseSpotCaches;
import 'package:ccs_app/features/spots/models/spot_version.dart'
    show spotCacheKey;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/data/spot_cache.dart';

Future<void> loadApprovedSpotsFromLocalCache({
  required int generation,
  required String scope,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!spotSyncIsCurrent(generation, scope)) return;
    final rawJson = prefs.getString('${approvedSpotCacheStorageKey}_$scope');
    if (rawJson == null || rawJson.trim().isEmpty) return;
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) return;

    final cachedSpots = <String, CarSpot>{};
    for (final item in decoded) {
      final spot = carSpotFromLocalCacheData(item);
      if (spot != null && approvedSpotIsVisibleForCurrentUser(spot)) {
        cachedSpots[spotCacheKey(spot)] = spot;
      }
    }
    if (cachedSpots.isEmpty || !spotSyncIsCurrent(generation, scope)) return;
    firebaseSpotCacheBySource['approved'] = cachedSpots;
    publishFirebaseSpotCaches();
    firestoreDebugTracker.recordRead('local cache: approved spots', 0);
  } catch (error) {
    debugPrint('Approved spots local cache load failed: $error');
  }
}
