import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

String spotNotificationOwnerUid(CarSpot spot) {
  final ownerUid = spot.ownerUid.trim();
  if (ownerUid.isNotEmpty) {
    return ownerUid;
  }

  return spot.addedByUid.trim();
}
