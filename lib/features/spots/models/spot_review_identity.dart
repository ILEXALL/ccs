import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

String localDayKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}$month$day';
}

String localDayKeyFromMillis(int millis) {
  if (millis <= 0) {
    return '';
  }

  return localDayKey(DateTime.fromMillisecondsSinceEpoch(millis));
}

String safeDailyCounterPathPart(String value) {
  return value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}

String spotReviewKey(CarSpot spot) {
  if (spot.id.trim().isNotEmpty) {
    return spot.id.trim();
  }

  final safeName = spot.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  return safeName.isEmpty ? 'demo_spot' : 'demo_$safeName';
}
