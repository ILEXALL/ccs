import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/controllers/map_start_position.dart';
import 'package:ccs_app/core/location/coordinates.dart' show isValidLatLng;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;

Future<LatLng?> currentMapStartLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse)
      return null;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final point = LatLng(position.latitude, position.longitude);
    return isValidLatLng(point) ? point : null;
  } catch (_) {
    return null;
  }
}

LatLng loadedSpotsMapCenter() =>
    spotsMidpoint(approvedPublicSpots().map((spot) => spot.coordinates));
