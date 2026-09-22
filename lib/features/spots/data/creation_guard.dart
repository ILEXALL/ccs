import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show minimumPermanentSpotDistanceMeters;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;

bool spotBlocksPermanentSpotCreation(CarSpot spot) {
  if (spot.status == SpotStatus.rejected) {
    return false;
  }

  if (spot.isTemporary && spot.isExpired) {
    return false;
  }

  return true;
}

Future<CarSpot?> findNearbySpotBlockingPermanentSpotCreation(
  LatLng location, {
  String? ignoreSpotId,
}) async {
  List<CarSpot> existingSpots;

  try {
    final snapshot = await spotsCollection().debugGet(
      const GetOptions(source: Source.server),
    );
    existingSpots = snapshot.docs
        .map((doc) => CarSpot.fromFirestore(doc))
        .toList();
  } catch (_) {
    existingSpots = reviewSpots.value;
  }

  CarSpot? nearestSpot;
  var nearestDistance = double.infinity;

  for (final spot in existingSpots) {
    if (ignoreSpotId != null &&
        ignoreSpotId.isNotEmpty &&
        spot.id == ignoreSpotId) {
      continue;
    }

    if (!spotBlocksPermanentSpotCreation(spot)) {
      continue;
    }

    final distance = distanceBetweenLatLngMeters(location, spot.coordinates);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestSpot = spot;
    }
  }

  if (nearestSpot == null ||
      nearestDistance >= minimumPermanentSpotDistanceMeters) {
    return null;
  }

  return nearestSpot;
}
