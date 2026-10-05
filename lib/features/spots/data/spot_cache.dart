import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        doubleFromFirebase,
        intFromFirebase,
        mapFromFirebase,
        stringFromFirebase,
        stringListFromFirebase;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show
        firebaseSpotCacheBySource,
        spotSyncGeneration,
        spotSyncIsCurrent,
        spotSyncScope;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show openingHoursFromFirebase, openingHoursToFirebase;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusFromFirebase, spotStatusName;

// v2 deliberately ignores the old shared/incomplete cache and delta cursor.
const String approvedSpotCacheStorageKey = 'approved_spots_local_cache_v2';

Map<String, Object?> carSpotToLocalCacheData(CarSpot spot) {
  return {
    'id': spot.id,
    'name': spot.name,
    'cityCountry': spot.cityCountry,
    'countryCode': spot.effectiveCountryCode,
    'lat': spot.coordinates.latitude,
    'lng': spot.coordinates.longitude,
    'description': spot.description,
    'categories': spot.categories,
    'likeCount': spot.likeCount,
    'commentCount': spot.commentCount,
    'photoUrl': spot.photoUrl,
    'photoUrls': spot.photoUrls,
    'visibility': spot.visibility,
    'sharedGroupIds': spot.sharedGroupIds,
    'sharedGroups': spot.sharedGroups,
    'reelLink': spot.reelLink,
    'contactPhone': spot.contactPhone,
    'contactInstagram': spot.contactInstagram,
    'contactEmail': spot.contactEmail,
    'openingHours': openingHoursToFirebase(spot.openingHours),
    'ownerUid': spot.ownerUid,
    'ownerUsername': spot.ownerUsername,
    'bestTime': spot.bestTime,
    'parking': spot.parking,
    'roadQuality': spot.roadQuality,
    'lowCarFriendly': spot.lowCarFriendly,
    'policeRisk': spot.policeRisk,
    'traffic': spot.traffic,
    'lighting': spot.lighting,
    'crowd': spot.crowd,
    'addedBy': spot.addedBy,
    'addedByUid': spot.addedByUid,
    'status': spotStatusName(spot.status),
    'createdAtMillis': spot.createdAtMillis,
    'updatedAtMillis': spot.updatedAtMillis,
    'isTemporary': spot.isTemporary,
    'startsAtMillis': spot.startsAtMillis,
    'expiresAtMillis': spot.expiresAtMillis,
    'showOnMapAtMillis': spot.showOnMapAtMillis,
    'verifiedOnly': spot.verifiedOnly,
    'rejectionReason': spot.rejectionReason,
    'reviewedBy': spot.reviewedBy,
    'reviewedByUid': spot.reviewedByUid,
  };
}

CarSpot? carSpotFromLocalCacheData(Object? value) {
  try {
    final data = mapFromFirebase(value);
    final id = stringFromFirebase(data['id'], '');
    if (id.isEmpty) {
      return null;
    }

    final coordinates = LatLng(
      doubleFromFirebase(data['lat'], 56.9496),
      doubleFromFirebase(data['lng'], 24.1052),
    );

    return CarSpot(
      id: id,
      name: stringFromFirebase(data['name'], 'Untitled spot'),
      cityCountry: stringFromFirebase(data['cityCountry'], 'Riga, Latvia'),
      countryCode: stringFromFirebase(data['countryCode'], ''),
      coordinates: coordinates,
      description: stringFromFirebase(
        data['description'],
        'Submitted community car spot.',
      ),
      categories: stringListFromFirebase(data['categories'], const ['Photo']),
      likeCount: math.max(0, intFromFirebase(data['likeCount'], 0)),
      commentCount: math.max(0, intFromFirebase(data['commentCount'], 0)),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      photoUrls: stringListFromFirebase(data['photoUrls'], const []),
      reelLink: stringFromFirebase(data['reelLink'], ''),
      contactPhone: stringFromFirebase(data['contactPhone'], ''),
      contactInstagram: stringFromFirebase(data['contactInstagram'], ''),
      contactEmail: stringFromFirebase(data['contactEmail'], ''),
      openingHours: openingHoursFromFirebase(data['openingHours']),
      ownerUid: stringFromFirebase(data['ownerUid'], ''),
      ownerUsername: stringFromFirebase(data['ownerUsername'], ''),
      bestTime: stringFromFirebase(data['bestTime'], 'Not reviewed'),
      parking: stringFromFirebase(data['parking'], 'Not reviewed'),
      roadQuality: stringFromFirebase(data['roadQuality'], 'Not reviewed'),
      lowCarFriendly: data['lowCarFriendly'] == true,
      policeRisk: stringFromFirebase(data['policeRisk'], 'Not reviewed'),
      traffic: stringFromFirebase(data['traffic'], 'Not reviewed'),
      lighting: stringFromFirebase(data['lighting'], 'Not reviewed'),
      crowd: stringFromFirebase(data['crowd'], 'Not reviewed'),
      addedBy: stringFromFirebase(data['addedBy'], 'ccs_driver'),
      addedByUid: stringFromFirebase(data['addedByUid'], ''),
      status: spotStatusFromFirebase(data['status']),
      createdAtMillis: intFromFirebase(data['createdAtMillis'], 0),
      updatedAtMillis: intFromFirebase(data['updatedAtMillis'], 0),
      visibility: stringFromFirebase(data['visibility'], 'public'),
      sharedGroupIds: stringListFromFirebase(data['sharedGroupIds'], const []),
      sharedGroups:
          (data['sharedGroups'] is List
                  ? data['sharedGroups'] as List
                  : const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
      isTemporary: data['isTemporary'] == true,
      startsAtMillis: data['startsAtMillis'] is num
          ? (data['startsAtMillis'] as num).toInt()
          : null,
      expiresAtMillis: data['expiresAtMillis'] is num
          ? (data['expiresAtMillis'] as num).toInt()
          : null,
      showOnMapAtMillis: data['showOnMapAtMillis'] is num
          ? (data['showOnMapAtMillis'] as num).toInt()
          : null,
      verifiedOnly: data['verifiedOnly'] == true,
      rejectionReason: stringFromFirebase(data['rejectionReason'], ''),
    );
  } catch (error) {
    debugPrint('Could not read cached spot: $error');
    return null;
  }
}

bool approvedSpotIsVisibleForCurrentUser(CarSpot spot) {
  return canViewGroupSpot(spot) &&
      spot.status == SpotStatus.approved &&
      spot.isVisibleNow &&
      (!spot.verifiedOnly || currentUserCanUseVerifiedOnlySpots);
}

int _approvedSpotCacheWriteSequence = 0;

Future<void> saveApprovedSpotsToLocalCache() async {
  final scope = spotSyncScope;
  final generation = spotSyncGeneration;
  if (scope == null || !spotSyncIsCurrent(generation, scope)) return;
  final sequence = ++_approvedSpotCacheWriteSequence;
  final approvedSpots =
      (firebaseSpotCacheBySource['approved'] ?? const <String, CarSpot>{})
          .values
          .where(approvedSpotIsVisibleForCurrentUser)
          .map(carSpotToLocalCacheData)
          .toList();
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!spotSyncIsCurrent(generation, scope) ||
        sequence != _approvedSpotCacheWriteSequence) {
      return;
    }
    await prefs.setString(
      '${approvedSpotCacheStorageKey}_$scope',
      jsonEncode(approvedSpots),
    );
  } catch (error) {
    debugPrint('Approved spots local cache save failed: $error');
  }
}
