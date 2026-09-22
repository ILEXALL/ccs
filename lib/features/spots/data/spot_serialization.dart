import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show openingHoursToFirebase;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show spotStatusName;

Map<String, Object?> spotToFirestoreData(
  CarSpot spot, {
  bool includeCreatedAt = false,
}) {
  final data = <String, Object?>{
    'name': spot.name,
    'cityCountry': spot.cityCountry,
    'countryCode': spot.effectiveCountryCode,
    'lat': spot.coordinates.latitude,
    'lng': spot.coordinates.longitude,
    'coordinates': GeoPoint(
      spot.coordinates.latitude,
      spot.coordinates.longitude,
    ),
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
    'verifiedOnly': spot.verifiedOnly,
    'rejectionReason': spot.rejectionReason,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (spot.isTemporary) {
    data['isTemporary'] = true;
    data['startsAt'] = spot.startsAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    data['expiresAt'] = spot.expiresAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
    data['showOnMapAt'] = spot.showOnMapAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.showOnMapAtMillis!);
  } else {
    data['isTemporary'] = false;
    data['startsAt'] = null;
    data['expiresAt'] = null;
    data['showOnMapAt'] = null;
  }

  if (includeCreatedAt) {
    data['createdAt'] = FieldValue.serverTimestamp();
  }

  return data;
}
