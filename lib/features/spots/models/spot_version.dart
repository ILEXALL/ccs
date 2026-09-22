import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

String spotCacheKey(CarSpot spot) {
  if (spot.id.trim().isNotEmpty) {
    return spot.id.trim();
  }

  return '${spot.name}_${spot.addedByUid}_${spot.createdAtMillis}';
}

int spotVersionFreshnessMillis(CarSpot spot) {
  if (spot.updatedAtMillis > 0) {
    return spot.updatedAtMillis;
  }
  return spot.createdAtMillis;
}

CarSpot preferredSpotVersion(CarSpot existing, CarSpot candidate) {
  final existingFreshness = spotVersionFreshnessMillis(existing);
  final candidateFreshness = spotVersionFreshnessMillis(candidate);

  if (candidateFreshness > existingFreshness) {
    return candidate;
  }
  if (candidateFreshness < existingFreshness) {
    return existing;
  }

  // If two sources momentarily report the same revision but disagree about a
  // temporary reveal time, prefer the more restrictive (later) reveal. This
  // prevents an old location from flashing on the map before the edited
  // showOnMapAt time while listeners converge.
  if (existing.isTemporary && candidate.isTemporary) {
    final existingReveal = existing.effectiveShowOnMapAtMillis ?? 0;
    final candidateReveal = candidate.effectiveShowOnMapAtMillis ?? 0;
    if (existingReveal != candidateReveal) {
      return candidateReveal > existingReveal ? candidate : existing;
    }
  }

  return candidate;
}
