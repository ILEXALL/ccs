import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'package:ccs_app/features/notifications/data/badge_sync.dart'
    show observeLoadedSpotsForBadges;
import 'package:ccs_app/features/spots/data/saved_spots.dart'
    show restoreSavedSpotsFromFirebaseCache;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, submittedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart';
import 'package:ccs_app/features/spots/models/spot_version.dart';

void publishFirebaseSpotCaches() {
  final merged = <String, CarSpot>{};

  for (final sourceSpots in firebaseSpotCacheBySource.values) {
    for (final entry in sourceSpots.entries) {
      final existing = merged[entry.key];
      merged[entry.key] = existing == null
          ? entry.value
          : preferredSpotVersion(existing, entry.value);
    }
  }

  final firebaseSpots = merged.values.toList()
    ..sort(
      (first, second) =>
          second.createdAtMillis.compareTo(first.createdAtMillis),
    );

  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  reviewSpots.value = firebaseSpots.where(canViewGroupSpot).toList();
  observeLoadedSpotsForBadges();
  submittedSpots.value = firebaseSpots
      .where((spot) => spot.addedByUid == currentUid)
      .toList();
  restoreSavedSpotsFromFirebaseCache();
}
