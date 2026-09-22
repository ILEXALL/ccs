import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, meetNotificationsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension, FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

Future<void> createMeetSpotNotificationsForNearbyUsers(CarSpot spot) async {
  if (spot.isGroupSpot) return;
  if (spot.id.trim().isEmpty || !spot.categories.contains('Meet')) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .debugGet(null, 'live location: expiration cleanup query');
  final batch = FirebaseFirestore.instance.batch();
  var writes = 0;

  for (final doc in activeLocations.docs) {
    final liveLocation = LiveLocationData.fromFirestore(doc);

    if (liveLocation.uid == spot.addedByUid || !liveLocation.isActive) {
      continue;
    }

    final distanceMeters = distanceBetweenLatLngMeters(
      spot.coordinates,
      liveLocation.coordinates,
    );

    if (distanceMeters > 50000) {
      continue;
    }

    final notificationId = '${spot.id}_${liveLocation.uid}';
    final notificationRef = meetNotificationsCollection().doc(notificationId);
    batch.debugSet(notificationRef, {
      'userId': liveLocation.uid,
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'lat': spot.coordinates.latitude,
      'lng': spot.coordinates.longitude,
      'coordinates': GeoPoint(
        spot.coordinates.latitude,
        spot.coordinates.longitude,
      ),
      'distanceMeters': distanceMeters.round(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    writes++;
  }

  if (writes > 0) {
    await batch.debugCommit();
  }
}
