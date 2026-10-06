import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/models/spot_presence_grouping.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, stringListFromFirebase, uniqueNonEmptyStrings;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/location/coordinates.dart'
    show normalizedHeadingDegrees, safeLatLngFromPosition, usableLiveFix;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show liveLocationBackgroundChannel;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/data/live_location_audience.dart'
    show publicLiveLocationVisibleToUserIds;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show updateCurrentUserPresenceFields;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/widgets/live_location_dialogs.dart'
    show
        liveLocationDurationLabel,
        showLiveLocationDurationDialog,
        showLiveLocationSharingDisclaimer;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserRegionIsRestricted;
import 'package:ccs_app/features/notifications/data/friend_location_notifications.dart'
    show notifyFriendsLiveLocationStartedNow;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show checkGpsCountryAchievement, checkGpsSpotVisits;
import 'package:ccs_app/shared/models/user_role.dart' show roleName;
import 'package:ccs_app/shared/widgets/region_unavailable_dialog.dart'
    show showRegionFeatureUnavailableDialog;
import 'map_session.dart';
import 'map_config.dart';

/// Coordinates sharing behavior using screen-owned state and lifecycle.
class MapSharingController implements MapSharingActions {
  final MapSession host;
  MapSharingController(this.host);

  @override
  void ensureNativeLiveLocationBackgroundService(
    User firebaseUser,
    LiveLocationData ownLocation,
  ) {
    final promptAt = DateTime.fromMillisecondsSinceEpoch(
      ownLocation.promptAtMillis,
    );
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      ownLocation.expiresAtMillis,
    );
    final visibleToUserIds = ownLocation.visibleToUserIds.isEmpty
        ? publicLiveLocationVisibleToUserIds(firebaseUser.uid)
        : ownLocation.visibleToUserIds;
    final shareScope = ownLocation.shareScope.trim().isEmpty
        ? 'public'
        : ownLocation.shareScope;
    final signature = [
      visibleToUserIds.join(','),
      shareScope,
      ownLocation.promptAtMillis,
      ownLocation.expiresAtMillis,
    ].join('|');

    if (host.nativeLiveLocationBackgroundSignature == signature) {
      return;
    }

    host.nativeLiveLocationBackgroundSignature = signature;
    unawaited(
      startNativeLiveLocationBackgroundService(
        uid: firebaseUser.uid,
        visibleToUserIds: visibleToUserIds,
        shareScope: shareScope,
        promptAt: promptAt,
        expiresAt: expiresAt,
      ),
    );
  }

  @override
  void ensureLiveLocationUploadLoop() {
    if (host.liveLocationUploadTimer != null) {
      return;
    }

    host.liveLocationUploadTimer = Timer.periodic(
      mapLiveLocationUploadInterval,
      (_) => uploadLatestLiveLocation(),
    );
  }

  @override
  void cancelLiveLocationTimers({bool keepUploadTimer = false}) {
    host.liveLocationPromptTimer?.cancel();
    host.liveLocationPromptTimer = null;
    host.liveLocationAutoStopTimer?.cancel();
    host.liveLocationAutoStopTimer = null;

    if (!keepUploadTimer) {
      host.liveLocationUploadTimer?.cancel();
      host.liveLocationUploadTimer = null;
    }
  }

  @override
  void scheduleLiveLocationTimers() {
    final expiresAt = host.liveLocationExpiresAt;

    host.liveLocationPromptTimer?.cancel();
    host.liveLocationPromptTimer = null;
    host.liveLocationAutoStopTimer?.cancel();

    if (!host.isSharingLiveLocation || expiresAt == null) {
      return;
    }

    final now = DateTime.now();
    final autoStopDelay = expiresAt.difference(now);

    host.liveLocationAutoStopTimer = Timer(
      autoStopDelay.isNegative ? Duration.zero : autoStopDelay,
      stopLiveLocationSharing,
    );
  }

  @override
  Future<void> toggleLiveLocationSharing(bool enabled) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (enabled) {
      if (currentUserRegionIsRestricted) {
        await showRegionFeatureUnavailableDialog(viewContext);
        return;
      }
      await startLiveLocationSharing();
    } else {
      await stopLiveLocationSharing();
    }
  }

  @override
  Future<void> startNativeLiveLocationBackgroundService({
    required String uid,
    required List<String> visibleToUserIds,
    required String shareScope,
    required DateTime promptAt,
    required DateTime expiresAt,
  }) async {
    try {
      await liveLocationBackgroundChannel.invokeMethod('start', {
        'uid': uid,
        'visibleToUserIds': visibleToUserIds,
        'shareScope': shareScope,
        'promptAtMillis': promptAt.millisecondsSinceEpoch,
        'expiresAtMillis': expiresAt.millisecondsSinceEpoch,
        'uploadIntervalSeconds': mapLiveLocationUploadInterval.inSeconds,
        'minimumUploadDistanceMeters':
            mapLiveLocationMinimumUploadDistanceMeters,
      });
    } on MissingPluginException {
      // Native background tracking is not wired yet. Foreground sharing still works.
    } catch (_) {}
  }

  @override
  Future<void> stopNativeLiveLocationBackgroundService() async {
    try {
      await liveLocationBackgroundChannel.invokeMethod('stop');
    } on MissingPluginException {
      // Native background tracking is not wired yet.
    } catch (_) {}
  }

  @override
  Future<void> startLiveLocationSharing() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (currentUserRegionIsRestricted) {
      await showRegionFeatureUnavailableDialog(viewContext);
      return;
    }
    if (host.isTogglingLiveLocation) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before sharing your live location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    host.updateMap(() => host.isTogglingLiveLocation = true);

    final acceptedDisclaimer = await showLiveLocationSharingDisclaimer(
      viewContext,
    );
    if (!(host.mounted && viewContext.mounted)) {
      return;
    }
    if (!acceptedDisclaimer) {
      host.updateMap(() => host.isTogglingLiveLocation = false);
      return;
    }

    final shareDuration = await showLiveLocationDurationDialog(viewContext);
    if (!(host.mounted && viewContext.mounted)) {
      return;
    }
    if (shareDuration == null) {
      host.updateMap(() => host.isTogglingLiveLocation = false);
      return;
    }

    host.liveLocationShareDuration = shareDuration;

    final position = await host.navigation.getMapUserPosition(showErrors: true);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      host.updateMap(() => host.isTogglingLiveLocation = false);
      return;
    }

    final visibleToUserIds = publicLiveLocationVisibleToUserIds(
      firebaseUser.uid,
    );
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    unawaited(checkGpsCountryAchievement(viewContext, position));
    unawaited(checkGpsSpotVisits(position));

    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = host.navigation.headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
      shareDuration: shareDuration,
      visibleToUserIds: visibleToUserIds,
      visibleToChatId: '',
      visibleToChatName: '',
      shareScope: 'public',
    );

    final promptAt = host.liveLocationPromptAt;
    final expiresAt = host.liveLocationExpiresAt;
    if (promptAt != null && expiresAt != null) {
      unawaited(
        startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: visibleToUserIds,
          shareScope: 'public',
          promptAt: promptAt,
          expiresAt: expiresAt,
        ),
      );
    }

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    host.updateMap(() {
      host.currentUserLocation = location;
      host.displayedUserLocation = location;
      host.lastGpsUserLocation = location;
      host.lastUploadedLiveLocation = location;
      host.lastGpsUserLocationAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = speed;
      host.isSharingLiveLocation = true;
      host.isTogglingLiveLocation = false;
    });

    host.navigation.startNavigationTracking();
    host.navigation.updateFollowCamera(location, heading);

    host.liveLocationUploadTimer?.cancel();
    host.liveLocationUploadTimer = Timer.periodic(
      mapLiveLocationUploadInterval,
      (_) => uploadLatestLiveLocation(),
    );

    ScaffoldMessenger.of(viewContext).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: CcsText(
          'Live location sharing is on for ${liveLocationDurationLabel(shareDuration)}.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Future<void> uploadLatestLiveLocation() async {
    if (!host.isSharingLiveLocation) {
      return;
    }

    final position = await host.navigation.getMapUserPosition(
      showErrors: false,
    );

    if (position == null || !host.mounted) {
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = host.navigation.headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );
    final lastUploadedLocation = host.lastUploadedLiveLocation;
    final movedSinceLastUpload = lastUploadedLocation == null
        ? mapLiveLocationMinimumUploadDistanceMeters
        : const Distance().as(LengthUnit.Meter, lastUploadedLocation, location);

    // Upload live location every 60 seconds while sharing is active.
    // Local marker still updates smoothly between Firebase writes.
    if (mapLiveLocationMinimumUploadDistanceMeters > 0 &&
        movedSinceLastUpload < mapLiveLocationMinimumUploadDistanceMeters) {
      host.updateMap(() {
        host.currentUserLocation = location;
        host.displayedUserLocation ??= location;
        host.lastGpsUserLocation = location;
        host.lastGpsUserLocationAt = DateTime.now();
        host.currentUserHeadingDegrees = heading;
        host.currentUserSpeedMetersPerSecond = speed;
      });

      if (host.mapCenteredOnCurrentUser) {
        host.navigation.updateFollowCamera(
          host.displayedUserLocation ?? location,
          heading,
        );
      }
      return;
    }

    await writeLiveLocation(
      position,
      renewWindow: false,
      headingDegrees: heading,
    );

    if (!host.mounted) {
      return;
    }

    host.updateMap(() {
      host.currentUserLocation = location;
      host.displayedUserLocation ??= location;
      host.lastGpsUserLocation = location;
      host.lastUploadedLiveLocation = location;
      host.lastGpsUserLocationAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = speed;
    });

    if (host.mapCenteredOnCurrentUser) {
      host.navigation.updateFollowCamera(
        host.displayedUserLocation ?? location,
        heading,
      );
    }
  }

  @override
  Future<void> recordNearbySpotVisit(Position position, User user) async {
    if (FirebaseAuth.instance.currentUser?.uid == user.uid)
      await checkGpsSpotVisits(position);
  }

  @override
  Future<void> writeLiveLocation(
    Position position, {
    required bool renewWindow,
    double? headingDegrees,
    Duration? shareDuration,
    List<String>? visibleToUserIds,
    String? visibleToChatId,
    String? visibleToChatName,
    String? shareScope,
  }) async {
    if (!usableLiveFix(position)) {
      if (position.isMocked) unawaited(checkGpsSpotVisits(position));
      throw StateError(
        'Waiting for an accurate GPS fix. Move outdoors and try again.',
      );
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final now = DateTime.now();
    final duration = shareDuration ?? host.liveLocationShareDuration;
    final expiresAt = renewWindow
        ? (host.isSharingLiveLocation &&
                      (host.liveLocationExpiresAt?.isAfter(now) ?? false)
                  ? host.liveLocationExpiresAt!
                  : now)
              .add(duration)
        : host.liveLocationExpiresAt ?? now.add(duration);
    final promptAt = expiresAt;

    host.liveLocationShareDuration = duration;
    host.liveLocationPromptAt = promptAt;
    host.liveLocationExpiresAt = expiresAt;

    final docRef = liveLocationsCollection().doc(firebaseUser.uid);
    Map<String, dynamic>? existingData;

    if (visibleToUserIds == null ||
        visibleToChatId == null ||
        visibleToChatName == null ||
        shareScope == null) {
      final existingSnapshot = await docRef.debugGet();
      existingData = existingSnapshot.data();
    }

    final nextVisibleToUserIds = uniqueNonEmptyStrings(
      visibleToUserIds ??
          stringListFromFirebase(existingData?['visibleToUserIds'], [
            firebaseUser.uid,
          ]),
    );
    final nextVisibleToChatId =
        visibleToChatId ??
        stringFromFirebase(existingData?['visibleToChatId'], '');
    final nextVisibleToChatName =
        visibleToChatName ??
        stringFromFirebase(existingData?['visibleToChatName'], '');
    final nextShareScope =
        shareScope ?? stringFromFirebase(existingData?['shareScope'], '');

    await docRef.debugSet({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'name': currentUser.name,
      'photoUrl': currentUser.photoUrl,
      'role': roleName(currentUser.role),
      'verified': currentUser.verified,
      'heading': normalizedHeadingDegrees(
        headingDegrees ?? position.heading,
        fallback: host.currentUserHeadingDegrees,
      ),
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'accuracy': position.accuracy,
      'recordedAtMillis': position.timestamp.millisecondsSinceEpoch,
      'isMocked': position.isMocked,
      'visibleToUserIds': nextVisibleToUserIds.isEmpty
          ? [firebaseUser.uid]
          : nextVisibleToUserIds,
      'visibleToChatId': nextVisibleToChatId,
      'visibleToChatName': nextVisibleToChatName,
      'shareScope': nextShareScope,
      'shareDurationMinutes': duration.inMinutes,
      'promptAt': Timestamp.fromDate(promptAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Use the newly saved sample for server-side five-minute arrival tracking.
    unawaited(sendPushNotificationEvent({'type': 'friend_at_spot'}));
    if (!position.isMocked && position.accuracy <= spotPresenceRadiusMeters) {
      unawaited(recordNearbySpotVisit(position, firebaseUser));
    }

    await updateCurrentUserPresenceFields({
      'isSharingLiveLocation': true,
      'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
      'liveLocationShareDurationMinutes': duration.inMinutes,
      'liveLocationVisibleToUserIds': nextVisibleToUserIds.isEmpty
          ? [firebaseUser.uid]
          : nextVisibleToUserIds,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'isOnline': true,
    }, label: 'presence: current user live location heartbeat');

    if (renewWindow) {
      await notifyFriendsLiveLocationStartedNow(
        coordinates: LatLng(position.latitude, position.longitude),
      );
    }

    if (host.mounted) {
      scheduleLiveLocationTimers();
    }
  }

  @override
  Future<void> stopLiveLocationSharing() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    host.liveLocationUploadTimer?.cancel();
    host.liveLocationUploadTimer = null;
    cancelLiveLocationTimers(keepUploadTimer: true);
    host.nativeLiveLocationBackgroundSignature = null;
    unawaited(stopNativeLiveLocationBackgroundService());

    if (firebaseUser != null) {
      await liveLocationsCollection().doc(firebaseUser.uid).debugDelete();
      unawaited(sendPushNotificationEvent({'type': 'friend_at_spot'}));
      await updateCurrentUserPresenceFields({
        'isSharingLiveLocation': false,
        'liveLocationExpiresAt': null,
        'liveLocationShareDurationMinutes': null,
        'liveLocationVisibleToUserIds': [],
      }, label: 'presence: current user live location stopped');
    }

    if (!host.mounted) {
      return;
    }

    host.updateMap(() {
      host.isSharingLiveLocation = false;
      host.isTogglingLiveLocation = false;
      host.liveLocationPromptAt = null;
      host.liveLocationExpiresAt = null;
      host.liveLocationShareDuration = const Duration(hours: 1);
      host.liveLocationPromptOpen = false;
      host.lastUploadedLiveLocation = null;
      if (firebaseUser != null) {
        host.presence.removeLiveLocationFromCaches(firebaseUser.uid);
      }
      host.liveLocations = host.liveLocations
          .where((location) => location.uid != firebaseUser?.uid)
          .toList();
    });
  }

  @override
  Future<void> continueLiveLocationSharing() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final position = await host.navigation.getMapUserPosition(showErrors: true);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      // A failed extension must not cancel the existing sharing window.
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    unawaited(checkGpsCountryAchievement(viewContext, position));
    unawaited(checkGpsSpotVisits(position));

    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = host.navigation.headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      await stopLiveLocationSharing();
      return;
    }

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
      shareDuration: host.liveLocationShareDuration,
      visibleToUserIds: publicLiveLocationVisibleToUserIds(firebaseUser.uid),
      visibleToChatId: '',
      visibleToChatName: '',
      shareScope: 'public',
    );

    final promptAt = host.liveLocationPromptAt;
    final expiresAt = host.liveLocationExpiresAt;
    if (promptAt != null && expiresAt != null) {
      unawaited(
        startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: publicLiveLocationVisibleToUserIds(
            firebaseUser.uid,
          ),
          shareScope: 'public',
          promptAt: promptAt,
          expiresAt: expiresAt,
        ),
      );
    }

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    host.updateMap(() {
      host.isSharingLiveLocation = true;
      host.currentUserLocation = location;
      host.lastUploadedLiveLocation = location;
      host.currentUserHeadingDegrees = heading;
    });

    if (host.mapCenteredOnCurrentUser) {
      host.navigation.updateFollowCamera(location, heading);
    }
  }

  @override
  Future<void> showLiveLocationRenewPrompt() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!(host.mounted && viewContext.mounted) ||
        !host.isSharingLiveLocation ||
        host.liveLocationPromptOpen) {
      return;
    }

    host.liveLocationPromptOpen = true;

    final keepSharing = await showDialog<bool>(
      context: viewContext,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const CcsText(
            'Continue sharing?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: CcsText(
            'Your live location has been shared for ${liveLocationDurationLabel(host.liveLocationShareDuration)}. Keep sharing it for another ${liveLocationDurationLabel(host.liveLocationShareDuration)}?',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const CcsText('Stop sharing'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: blue),
              child: const CcsText(
                'Continue sharing',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    host.liveLocationPromptOpen = false;

    if (!(host.mounted && viewContext.mounted) || !host.isSharingLiveLocation) {
      return;
    }

    if (keepSharing == true) {
      await continueLiveLocationSharing();
    } else if (keepSharing == false) {
      await stopLiveLocationSharing();
    } else {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            'No answer. Live location will stop automatically in 10 minutes.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }
}
