import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show uniqueNonEmptyStrings;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/location/coordinates.dart'
    show normalizedHeadingDegrees, usableLiveFix;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/data/chat_messages.dart'
    show sendChatMessage;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show userLocationLookupTimeout;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show updateCurrentUserPresenceFields;
import 'package:ccs_app/features/map/widgets/live_location_dialogs.dart'
    show
        liveLocationDurationLabel,
        showLiveLocationDurationDialog,
        showLiveLocationSharingDisclaimer;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserRegionIsRestricted;
import 'package:ccs_app/features/notifications/data/friend_location_notifications.dart'
    show notifyFriendsLiveLocationStartedNow;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show checkGpsCountryAchievement, checkGpsSpotVisits;
import 'package:ccs_app/shared/models/user_role.dart' show roleName;
import 'package:ccs_app/shared/widgets/region_unavailable_dialog.dart'
    show showRegionFeatureUnavailableDialog;

Future<Position?> getChatSharePosition(BuildContext context) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Turn on phone location first.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Location permission is needed to share your location.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: userLocationLookupTimeout,
      ),
    );
  } on TimeoutException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not find your location. Try again in a moment.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return null;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not share location: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return null;
  }
}

Future<void> shareChatLiveLocation(
  BuildContext context,
  ChatThreadData chat,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before sharing your location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return;
  }

  if (currentUserRegionIsRestricted) {
    await showRegionFeatureUnavailableDialog(context);
    return;
  }

  final otherDirectUserId = chat.memberIds.firstWhere(
    (uid) => uid.trim().isNotEmpty && uid != firebaseUser.uid,
    orElse: () => '',
  );
  final visibleToUserIds = uniqueNonEmptyStrings(
    chat.isGroup
        ? [firebaseUser.uid, ...chat.memberIds]
        : [firebaseUser.uid, otherDirectUserId],
  );

  if (visibleToUserIds.length <= 1) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'This chat has no one to share location with.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return;
  }

  final acceptedDisclaimer = await showLiveLocationSharingDisclaimer(context);
  if (!acceptedDisclaimer || !context.mounted) {
    return;
  }

  final shareDuration = await showLiveLocationDurationDialog(context);
  if (shareDuration == null || !context.mounted) {
    return;
  }

  final position = await getChatSharePosition(context);

  if (position != null && position.isMocked)
    unawaited(checkGpsSpotVisits(position));
  if (position == null || !usableLiveFix(position)) {
    return;
  }

  unawaited(checkGpsCountryAchievement(context, position));
  unawaited(checkGpsSpotVisits(position));

  final now = DateTime.now();
  final expiresAt = now.add(shareDuration);
  final promptAt = expiresAt;
  final chatTitle = chat.titleForCurrentUser(firebaseUser.uid);

  await liveLocationsCollection().doc(firebaseUser.uid).debugSet({
    'uid': firebaseUser.uid,
    'username': currentUser.username,
    'name': currentUser.name,
    'photoUrl': currentUser.photoUrl,
    'role': roleName(currentUser.role),
    'verified': currentUser.verified,
    'heading': normalizedHeadingDegrees(position.heading),
    'accuracy': position.accuracy,
    'isMocked': position.isMocked,
    'recordedAtMillis': position.timestamp.millisecondsSinceEpoch,
    'lat': position.latitude,
    'lng': position.longitude,
    'coordinates': GeoPoint(position.latitude, position.longitude),
    'visibleToUserIds': visibleToUserIds,
    'visibleToChatId': chat.id,
    'visibleToChatName': chatTitle,
    'shareScope': chat.isGroup ? 'group' : 'direct',
    'shareDurationMinutes': shareDuration.inMinutes,
    'promptAt': Timestamp.fromDate(promptAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await updateCurrentUserPresenceFields({
    'isSharingLiveLocation': true,
    'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
    'liveLocationShareDurationMinutes': shareDuration.inMinutes,
    'liveLocationVisibleToUserIds': visibleToUserIds,
    'lastSeenAt': FieldValue.serverTimestamp(),
    'isOnline': true,
  }, label: 'presence: current user live location started');

  await notifyFriendsLiveLocationStartedNow(
    coordinates: LatLng(position.latitude, position.longitude),
  );

  await sendChatMessage(
    chatId: chat.id,
    text: chat.isGroup
        ? 'Shared live location with this group.'
        : 'Shared live location with you.',
    chat: chat,
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: CcsText(
          chat.isGroup
              ? 'Location shared with this group for ${liveLocationDurationLabel(shareDuration)}.'
              : 'Location shared with this chat for ${liveLocationDurationLabel(shareDuration)}.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
