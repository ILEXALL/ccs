import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show doubleFromFirebase;

const LatLng fallbackRigaLatLng = LatLng(56.9496, 24.1052);

bool isValidLatLngValues(double? latitude, double? longitude) {
  return latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

bool isValidLatLng(LatLng? value) {
  return value != null && isValidLatLngValues(value.latitude, value.longitude);
}

LatLng safeLatLng(
  double? latitude,
  double? longitude, {
  LatLng fallback = fallbackRigaLatLng,
}) {
  if (isValidLatLngValues(latitude, longitude)) {
    return LatLng(latitude!, longitude!);
  }

  return fallback;
}

LatLng safeLatLngFromFirestoreCoordinates(
  Object? coordinates,
  Object? lat,
  Object? lng, {
  LatLng fallback = fallbackRigaLatLng,
}) {
  if (coordinates is GeoPoint) {
    return safeLatLng(
      coordinates.latitude,
      coordinates.longitude,
      fallback: fallback,
    );
  }

  return safeLatLng(
    doubleFromFirebase(lat, fallback.latitude),
    doubleFromFirebase(lng, fallback.longitude),
    fallback: fallback,
  );
}

LatLng? safeLatLngFromPosition(Position position) {
  if (!isValidLatLngValues(position.latitude, position.longitude)) {
    return null;
  }

  return LatLng(position.latitude, position.longitude);
}

bool usableLiveFix(Position position) =>
    !position.isMocked &&
    position.accuracy.isFinite &&
    position.accuracy >= 0 &&
    position.accuracy <= 50 &&
    DateTime.now().difference(position.timestamp).abs() <=
        const Duration(seconds: 30);

Future<String> detectCityCountryForCoordinates(LatLng coordinates) async {
  try {
    final placemarks = await placemarkFromCoordinates(
      coordinates.latitude,
      coordinates.longitude,
    );

    if (placemarks.isEmpty) {
      return 'Unknown location';
    }

    final place = placemarks.first;
    final city =
        [place.locality, place.subAdministrativeArea, place.administrativeArea]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Unknown city',
            );
    final country = (place.country ?? '').trim();

    return country.isEmpty ? city : '$city, $country';
  } catch (_) {
    return 'Unknown location';
  }
}

double distanceBetweenLatLngMeters(LatLng first, LatLng second) {
  if (!isValidLatLng(first) || !isValidLatLng(second)) {
    return double.infinity;
  }

  return const Distance().as(LengthUnit.Meter, first, second);
}

double normalizedHeadingDegrees(double value, {double fallback = 0}) {
  final safeFallback = fallback.isFinite && fallback >= 0
      ? fallback % 360
      : 0.0;

  if (!value.isFinite || value < 0) {
    return safeFallback;
  }

  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double headingRadiansForMap(double headingDegrees, double mapRotationDegrees) {
  return (headingDegrees - mapRotationDegrees) * math.pi / 180;
}

double headingRadiansForMapPinnedMarker(double headingDegrees) {
  return normalizedHeadingDegrees(headingDegrees) * math.pi / 180;
}

double bearingBetweenLatLngDegrees(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final deltaLng = (to.longitude - from.longitude) * math.pi / 180;

  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
  final bearing = math.atan2(y, x) * 180 / math.pi;

  return normalizedHeadingDegrees(bearing + 360);
}

LatLng projectLatLngMeters(
  LatLng origin,
  double bearingDegrees,
  double distanceMeters,
) {
  if (!isValidLatLng(origin) ||
      distanceMeters <= 0 ||
      !distanceMeters.isFinite) {
    return isValidLatLng(origin) ? origin : fallbackRigaLatLng;
  }

  const earthRadiusMeters = 6371000.0;
  final bearing = normalizedHeadingDegrees(bearingDegrees) * math.pi / 180;
  final angularDistance = distanceMeters / earthRadiusMeters;
  final lat1 = origin.latitude * math.pi / 180;
  final lng1 = origin.longitude * math.pi / 180;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angularDistance) +
        math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
  );
  final lng2 =
      lng1 +
      math.atan2(
        math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
        math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
      );

  return safeLatLng(
    lat2 * 180 / math.pi,
    lng2 * 180 / math.pi,
    fallback: origin,
  );
}

LatLng lerpLatLng(LatLng from, LatLng to, double amount) {
  if (!isValidLatLng(from)) {
    return isValidLatLng(to) ? to : fallbackRigaLatLng;
  }

  if (!isValidLatLng(to)) {
    return from;
  }

  final t = amount.clamp(0.0, 1.0).toDouble();
  return safeLatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
    fallback: from,
  );
}
