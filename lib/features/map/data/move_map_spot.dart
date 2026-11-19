import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/features/moderation/data/regional_access.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';

Future<void> moveMapSpot(
  String id,
  double lat,
  double lng,
  double originalLat,
  double originalLng,
) async {
  if (![lat, lng, originalLat, originalLng].every((v) => v.isFinite) ||
      lat.abs() > 90 ||
      lng.abs() > 180) {
    throw StateError('Invalid position.');
  }
  final ref = spotsCollection().doc(id);
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw StateError('This spot is no longer available.');
    final spot = CarSpot.fromFirestore(snapshot);
    if (!currentUserCanModerateSpot(spot)) {
      throw StateError('You do not have permission to move this spot.');
    }
    if ((spot.coordinates.latitude - originalLat).abs() > 0.0000001 ||
        (spot.coordinates.longitude - originalLng).abs() > 0.0000001) {
      throw StateError(
        'The position was changed by someone else. Cancel and try again.',
      );
    }
    transaction.update(ref, {
      'lat': lat,
      'lng': lng,
      'coordinates': GeoPoint(lat, lng),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}
