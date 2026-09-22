import 'dart:async';
import 'dart:math' as math;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show setAppIconBadgeCount;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show appIconBadgeSyncStarted, inAppBadges, notificationCenterUnreadCount;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show spotMatchesSelectedCountries;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;

void observeLoadedSpotsForBadges() {
  for (final spot in reviewSpots.value) {
    inAppBadges.observeSpot(
      spot.id,
      math.max(spot.createdAtMillis, spot.updatedAtMillis),
      own: spot.addedByUid == inAppBadges.uid,
      eligible:
          spot.status == SpotStatus.approved &&
          (spot.expiresAtMillis == null ||
              spot.expiresAtMillis! > DateTime.now().millisecondsSinceEpoch) &&
          spotMatchesSelectedCountries(spot) &&
          (!spot.verifiedOnly || currentUserCanUseVerifiedOnlySpots),
    );
  }
}

void startAppIconBadgeSync() {
  if (appIconBadgeSyncStarted) {
    return;
  }

  appIconBadgeSyncStarted = true;
  notificationCenterUnreadCount.addListener(() {
    unawaited(setAppIconBadgeCount(notificationCenterUnreadCount.value));
  });
  unawaited(setAppIconBadgeCount(notificationCenterUnreadCount.value));
}
