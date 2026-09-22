import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show liveLocationPushNotificationUrls;
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/friends/data/friends_repository.dart'
    show loadCurrentFriendUids;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show
        friendAtSpotRadiusMeters,
        friendLocationNotificationCooldown,
        friendNearbyRadiusMeters;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show loadCurrentLiveLocationForUser;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent, trySendPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show userNotificationPreferenceEnabled;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

String friendNearbyNotificationId(String userId, String friendUid) {
  return 'nearby_${userId}_$friendUid';
}

String friendSpotNotificationId(
  String userId,
  String friendUid,
  String spotId,
) {
  return 'spot_${userId}_${friendUid}_$spotId';
}

Future<bool> shouldCreateFriendLocationNotification(
  String notificationId,
) async {
  final snapshot = await userNotificationsCollection()
      .doc(notificationId)
      .debugGet();

  if (!snapshot.exists) {
    return true;
  }

  final data = snapshot.data() ?? {};
  final lastNotifiedAtMillis = timestampMillisFromFirebase(
    data['lastNotifiedAtMillis'],
  );

  if (lastNotifiedAtMillis <= 0) {
    return true;
  }

  final elapsedMillis =
      DateTime.now().millisecondsSinceEpoch - lastNotifiedAtMillis;
  return elapsedMillis >= friendLocationNotificationCooldown.inMilliseconds;
}

Future<void> createFriendLocationNotification({
  required String notificationId,
  required String userId,
  required LiveLocationData friendLocation,
  required String type,
  required double distanceMeters,
  CarSpot? spot,
}) async {
  if (!await shouldCreateFriendLocationNotification(notificationId)) {
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  await userNotificationsCollection().doc(notificationId).debugSet({
    'userId': userId,
    'type': type,
    'title': 'Live location',
    'body': type == 'friend_at_spot'
        ? '@${friendLocation.username} is at ${spot?.name ?? 'a spot'}.'
        : '@${friendLocation.username} is nearby.',
    'actorUserId': friendLocation.uid,
    'actorUsername': friendLocation.username,
    'friendUid': friendLocation.uid,
    'friendUsername': friendLocation.username,
    'friendName': friendLocation.name,
    'friendLat': friendLocation.coordinates.latitude,
    'friendLng': friendLocation.coordinates.longitude,
    'friendCoordinates': GeoPoint(
      friendLocation.coordinates.latitude,
      friendLocation.coordinates.longitude,
    ),
    'distanceMeters': distanceMeters.round(),
    'spotId': spot?.id ?? '',
    'spotName': spot?.name ?? '',
    'spotCategory': spot?.categories.isEmpty == true
        ? ''
        : spot?.categories.first ?? '',
    'read': false,
    'lastNotifiedAtMillis': nowMillis,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<bool> createCurrentUserFriendLocationNotification({
  required String notificationId,
  required String userId,
  required String type,
  required String settingName,
  required LatLng coordinates,
  required double distanceMeters,
  CarSpot? spot,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUserId = userId.trim();

  if (firebaseUser == null ||
      cleanUserId.isEmpty ||
      cleanUserId == firebaseUser.uid) {
    return false;
  }

  final allowed = await userNotificationPreferenceEnabled(
    cleanUserId,
    settingName,
  );
  if (!allowed) {
    return false;
  }

  if (!await shouldCreateFriendLocationNotification(notificationId)) {
    return false;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final spotName = spot?.name.trim() ?? '';
  final body = switch (type) {
    'friend_at_spot' =>
      '@${currentUser.username} is at ${spotName.isEmpty ? 'a spot' : spotName}.',
    'friend_live_sharing' =>
      '@${currentUser.username} is sharing live location.',
    _ => '@${currentUser.username} is on the map.',
  };

  await userNotificationsCollection().doc(notificationId).debugSet({
    'userId': cleanUserId,
    'type': type,
    'title': 'Live location',
    'body': body,
    'actorUserId': firebaseUser.uid,
    'actorUsername': currentUser.username,
    'friendUid': firebaseUser.uid,
    'friendUsername': currentUser.username,
    'friendName': currentUser.name,
    'friendLat': coordinates.latitude,
    'friendLng': coordinates.longitude,
    'friendCoordinates': GeoPoint(coordinates.latitude, coordinates.longitude),
    'distanceMeters': distanceMeters.round(),
    'spotId': spot?.id ?? '',
    'spotName': spotName,
    'spotCategory': spot?.categories.isEmpty == true
        ? ''
        : spot?.categories.first ?? '',
    'read': false,
    'lastNotifiedAtMillis': nowMillis,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  return true;
}

Future<void> notifyCurrentUserFriendsAboutSpotPresence({
  required LatLng coordinates,
  required CarSpot spot,
  required double distanceMeters,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || spot.id.trim().isEmpty) {
    return;
  }

  final friendUids = await loadCurrentFriendUids();
  for (final friendUid in friendUids) {
    await createCurrentUserFriendLocationNotification(
      notificationId: friendSpotNotificationId(
        friendUid,
        firebaseUser.uid,
        spot.id,
      ),
      userId: friendUid,
      type: 'friend_at_spot',
      settingName: 'friendAtSpotNotifications',
      coordinates: coordinates,
      distanceMeters: distanceMeters,
      spot: spot,
    );
  }

  unawaited(
    sendPushNotificationEvent({
      'type': 'friend_at_spot',
      'preferenceKey': 'friendAtSpotNotifications',
      'spotId': spot.id,
      'spotName': spot.name,
      'lat': coordinates.latitude,
      'lng': coordinates.longitude,
      'recipientUserIds': friendUids,
    }),
  );
}

Future<void> checkFriendLocationNotifications() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  final friendUids = await loadCurrentFriendUids();

  if (friendUids.isEmpty) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('visibleToUserIds', arrayContains: firebaseUser.uid)
      .debugGet(null, 'live location: friend active locations one-shot');

  final friendUidSet = friendUids.toSet();
  final friendLocations = activeLocations.docs
      .map((doc) => LiveLocationData.fromFirestore(doc))
      .where(
        (location) =>
            friendUidSet.contains(location.uid) &&
            location.uid != firebaseUser.uid &&
            location.visibleToUserIds.contains(firebaseUser.uid) &&
            location.isActive,
      )
      .toList();

  if (friendLocations.isEmpty) {
    return;
  }

  final currentLocation = await loadCurrentLiveLocationForUser(
    firebaseUser.uid,
  );
  final visibleApprovedSpots = approvedPublicSpots();

  for (final friendLocation in friendLocations) {
    if (currentLocation != null) {
      final distanceMeters = distanceBetweenLatLngMeters(
        currentLocation.coordinates,
        friendLocation.coordinates,
      );

      if (distanceMeters <= friendNearbyRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendNearbyNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_nearby',
          distanceMeters: distanceMeters,
        );
      }
    }

    for (final spot in visibleApprovedSpots) {
      if (spot.id.trim().isEmpty) {
        continue;
      }

      final distanceToSpotMeters = distanceBetweenLatLngMeters(
        friendLocation.coordinates,
        spot.coordinates,
      );

      if (distanceToSpotMeters <= friendAtSpotRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendSpotNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
            spot.id,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_at_spot',
          distanceMeters: distanceToSpotMeters,
          spot: spot,
        );
      }
    }
  }
}

Future<bool> notifyFriendsLiveLocationStartedNow({LatLng? coordinates}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    return false;
  }

  final liveCoordinates = coordinates ?? const LatLng(0, 0);
  final dispatchId =
      'friend_live_share_started_${firebaseUser.uid}_${DateTime.now().microsecondsSinceEpoch}';
  final senderUsername = currentUser.username.trim().isEmpty
      ? 'ccs_driver'
      : currentUser.username.trim();
  final event = <String, Object?>{
    'type': 'friend_live_sharing',
    'preferenceKey': 'friendLiveShareNotifications',
    'notificationId': dispatchId,
    'senderUsername': senderUsername,
    'lat': liveCoordinates.latitude,
    'lng': liveCoordinates.longitude,
    'title': 'Live location',
    'body': '@$senderUsername is sharing live location.',
  };

  // This dedicated endpoint derives the sender's friends, sends the FCM
  // notification, and enforces one live-location notification per sender
  // every 30 minutes across Android, iOS, app restarts, and multiple devices.
  //
  // Do not fall back to the legacy push route here. That route does not own the
  // server-side throttle and could bypass the 30-minute limit during an error.
  final delivered = await trySendPushNotificationEvent(
    event,
    endpoints: liveLocationPushNotificationUrls,
    deduplicate: false,
  );
  if (!delivered) {
    debugPrint('Live share push was not delivered: $dispatchId');
  }
  return delivered;
}
