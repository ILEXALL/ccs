import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show chatIdFromNotificationItem;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show chatsCollection, spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show spotNameFromNotificationBody;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;
import 'package:ccs_app/features/spots/data/spot_cache.dart'
    show approvedSpotIsVisibleForCurrentUser;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/data/spot_queries.dart'
    show approvedSpotsForCurrentUserQuery;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show firebaseApprovedSpotsListenLimit, upsertSpotIntoLocalImmediateCache;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;

Future<CarSpot?> spotForNotificationItem(NotificationCenterItem item) async {
  var cleanSpotId = item.spotId.trim();
  var cleanSpotName = item.spotName.trim();

  if (cleanSpotName.isEmpty) {
    cleanSpotName = spotNameFromNotificationBody(item.type, item.body).trim();
  }

  if (cleanSpotId.isEmpty) {
    final itemId = item.id.trim();
    final idMatch = RegExp(
      r'^(?:new_spot|temporary_event|spot_like|spot_comment|spot_review)_(.+)_[^_]+$',
    ).firstMatch(itemId);
    cleanSpotId = idMatch?.group(1)?.trim() ?? '';

    // Some older notification documents may have user ids or spot ids that
    // contain underscores. Prefer a best-effort prefix/suffix strip before
    // falling back to name lookup.
    if (cleanSpotId.isEmpty) {
      for (final prefix in [
        'temporary_event_',
        'spot_comment_',
        'spot_like_',
        'spot_review_',
        'new_spot_',
      ]) {
        if (!itemId.startsWith(prefix)) {
          continue;
        }

        final withoutPrefix = itemId.substring(prefix.length);
        final lastSeparator = withoutPrefix.lastIndexOf('_');
        if (lastSeparator > 0) {
          cleanSpotId = withoutPrefix.substring(0, lastSeparator).trim();
        }
        break;
      }
    }
  }

  if (cleanSpotId.isEmpty && cleanSpotName.isEmpty) {
    return null;
  }

  final cleanSpotNameLower = cleanSpotName.toLowerCase();

  bool matchesNotificationSpot(CarSpot spot) {
    if (cleanSpotId.isNotEmpty &&
        (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId)) {
      return true;
    }

    return cleanSpotNameLower.isNotEmpty &&
        spot.name.trim().toLowerCase() == cleanSpotNameLower;
  }

  CarSpot? firstMatchingLocalSpot() {
    for (final spots in [
      reviewSpots.value,
      approvedPublicSpots(),
      submittedSpots.value,
      savedSpots.value,
    ]) {
      for (final spot in spots) {
        if (matchesNotificationSpot(spot)) {
          return spot;
        }
      }
    }
    return null;
  }

  final localSpot = firstMatchingLocalSpot();
  // Review notifications must open the latest submitted edit, not a cached
  // approved version. Keep the normal cache fallback for offline viewing.
  if (item.type == 'spot_pending_review' &&
      userRoleIsStaff(currentUser.role) &&
      cleanSpotId.isNotEmpty) {
    try {
      final doc = await spotsCollection()
          .doc(cleanSpotId)
          .debugGet(
            const GetOptions(source: Source.server),
            'notification center: latest spot review',
          );
      if (doc.exists) return CarSpot.fromFirestore(doc);
      return null;
    } catch (error) {
      debugPrint('Latest spot review lookup failed: $error');
    }
  }
  if (localSpot != null) {
    return localSpot;
  }

  // Fast path for current/new notification documents that carry the real
  // Firestore document id. This can fail for older/backend notifications when
  // the id is stored only in nested data, is a review key, or rules require an
  // approved-spots query instead of direct document get, so we always continue
  // to the query fallbacks below instead of giving up.
  if (cleanSpotId.isNotEmpty) {
    try {
      final doc = await spotsCollection()
          .doc(cleanSpotId)
          .debugGet(null, 'notification center: open spot by id');
      if (doc.exists) {
        final spot = CarSpot.fromFirestore(doc);
        upsertSpotIntoLocalImmediateCache(spot);
        return spot;
      }
    } catch (error) {
      debugPrint('Notification spot id lookup failed: $error');
    }
  }

  // New spot notifications created by the push backend commonly have a body
  // like "Spot name in Riga, Latvia". Query by the parsed name so old
  // notifications still open even if their spotId was not copied to the
  // top-level Firestore notification document.
  if (cleanSpotName.isNotEmpty) {
    try {
      final snapshot = await spotsCollection()
          .where('name', isEqualTo: cleanSpotName)
          .limit(10)
          .debugGet(null, 'notification center: open spot by exact name');
      for (final doc in snapshot.docs) {
        final spot = CarSpot.fromFirestore(doc);
        if (approvedSpotIsVisibleForCurrentUser(spot) ||
            userRoleIsStaff(currentUser.role) ||
            spot.addedByUid == (FirebaseAuth.instance.currentUser?.uid ?? '')) {
          upsertSpotIntoLocalImmediateCache(spot);
          return spot;
        }
      }
    } catch (error) {
      debugPrint('Notification spot exact name lookup failed: $error');
    }
  }

  // Last-resort server fallback: load the approved visible set and match by id,
  // review key, or parsed name. This costs reads only when the user taps a
  // notification that cannot be resolved from the local cache/direct doc.
  try {
    final snapshot = await approvedSpotsForCurrentUserQuery()
        .limit(firebaseApprovedSpotsListenLimit)
        .debugGet(
          const GetOptions(source: Source.server),
          'notification center: open spot approved fallback',
        );
    for (final doc in snapshot.docs) {
      final spot = CarSpot.fromFirestore(doc);
      if (matchesNotificationSpot(spot)) {
        upsertSpotIntoLocalImmediateCache(spot);
        return spot;
      }
    }
  } catch (error) {
    debugPrint('Notification approved spot fallback lookup failed: $error');
  }

  return null;
}

Future<ChatThreadData?> chatForNotificationItem(
  NotificationCenterItem item,
) async {
  final cleanChatId = chatIdFromNotificationItem(item);
  if (cleanChatId.isEmpty) {
    return null;
  }

  try {
    final doc = await chatsCollection().doc(cleanChatId).debugGet();
    if (doc.exists) {
      return ChatThreadData.fromFirestore(doc);
    }
  } catch (_) {}

  return null;
}
