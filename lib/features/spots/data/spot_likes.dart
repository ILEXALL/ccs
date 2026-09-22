import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugQueryExtension,
        FirestoreDebugTransactionExtension,
        trackedQuerySnapshots;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/spots/models/spot_owner.dart'
    show spotNotificationOwnerUid;
import 'package:ccs_app/features/spots/data/spot_counters.dart'
    show updateSpotCountersLocally;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show localDayKey, safeDailyCounterPathPart, spotReviewKey;
import 'package:ccs_app/core/firestore/collections.dart'
    show spotLikesCollection;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_review.dart'
    show SpotReviewData;
import 'package:ccs_app/features/spots/widgets/spot_like_dialogs.dart'
    show showSpotLikeDailyLimitDialog, showSpotLikeSaveErrorDialog;

final currentUserLikedSpotIds = ValueNotifier<Set<String>>({});

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
currentUserLikedSpotsSubscription;

String? currentUserLikedSpotsSyncUid;

bool currentUserLikedSpotsSyncStarting = false;

const currentUserLikedSpotIdsStoragePrefix = 'current_user_liked_spot_ids_';

const spotLikeDailyToggleCountStoragePrefix = 'spot_like_daily_toggle_count_';

const int maxDailySpotLikeTogglesPerUserPerSpot = 4;

final Set<String> spotLikeTogglesInFlight = {};

String spotLikeDailyToggleCountStorageKey({
  required String spotId,
  required String userId,
  required String dayKey,
}) {
  return '$spotLikeDailyToggleCountStoragePrefix${safeDailyCounterPathPart(spotId)}_${safeDailyCounterPathPart(userId)}_${safeDailyCounterPathPart(dayKey)}';
}

Future<int> loadLocalSpotLikeDailyToggleCount({
  required String spotId,
  required String userId,
  required String dayKey,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(
          spotLikeDailyToggleCountStorageKey(
            spotId: spotId,
            userId: userId,
            dayKey: dayKey,
          ),
        ) ??
        0;
  } catch (_) {
    return 0;
  }
}

Future<void> saveLocalSpotLikeDailyToggleCount({
  required String spotId,
  required String userId,
  required String dayKey,
  required int count,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      spotLikeDailyToggleCountStorageKey(
        spotId: spotId,
        userId: userId,
        dayKey: dayKey,
      ),
      count,
    );
  } catch (_) {}
}

final currentUserLikedCommentIds = ValueNotifier<Set<String>>({});

final currentUserCommentLikeCountOverrides = ValueNotifier<Map<String, int>>(
  {},
);

const currentUserLikedCommentIdsStoragePrefix =
    'current_user_liked_comment_ids_';

String currentUserLikedSpotIdsStorageKey(String uid) {
  return '$currentUserLikedSpotIdsStoragePrefix$uid';
}

Future<void> loadCurrentUserLikedSpotIdsFromLocalCache() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';
  if (uid.isEmpty) {
    currentUserLikedSpotIds.value = {};
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(currentUserLikedSpotIdsStorageKey(uid));
    if (ids == null) {
      return;
    }

    currentUserLikedSpotIds.value = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  } catch (_) {}
}

Future<void> saveCurrentUserLikedSpotIdsToLocalCache() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';
  if (uid.isEmpty) {
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      currentUserLikedSpotIdsStorageKey(uid),
      currentUserLikedSpotIds.value.toList()..sort(),
    );
  } catch (_) {}
}

String currentUserLikedCommentIdsStorageKey(String uid) {
  return '$currentUserLikedCommentIdsStoragePrefix$uid';
}

Future<void> loadCurrentUserLikedCommentIdsFromLocalCache() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';
  if (uid.isEmpty) {
    currentUserLikedCommentIds.value = {};
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(currentUserLikedCommentIdsStorageKey(uid));
    if (ids == null) {
      return;
    }

    currentUserLikedCommentIds.value = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  } catch (_) {}
}

Future<void> saveCurrentUserLikedCommentIdsToLocalCache() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';
  if (uid.isEmpty) {
    return;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      currentUserLikedCommentIdsStorageKey(uid),
      currentUserLikedCommentIds.value.toList()..sort(),
    );
  } catch (_) {}
}

void setCurrentUserCommentLikedLocally(String commentId, bool liked) {
  final cleanCommentId = commentId.trim();
  if (cleanCommentId.isEmpty) {
    return;
  }

  final nextLikedIds = {...currentUserLikedCommentIds.value};
  if (liked) {
    nextLikedIds.add(cleanCommentId);
  } else {
    nextLikedIds.remove(cleanCommentId);
  }

  currentUserLikedCommentIds.value = nextLikedIds;
  unawaited(saveCurrentUserLikedCommentIdsToLocalCache());
}

int currentCommentLikeCount(SpotReviewData review) {
  return currentUserCommentLikeCountOverrides.value[review.id] ??
      review.likeCount;
}

void setCommentLikeCountLocally(String commentId, int count) {
  final cleanCommentId = commentId.trim();
  if (cleanCommentId.isEmpty) {
    return;
  }

  currentUserCommentLikeCountOverrides.value = {
    ...currentUserCommentLikeCountOverrides.value,
    cleanCommentId: math.max(0, count),
  };
}

Stream<bool> watchCurrentUserLikedCommentFromCache(String commentId) {
  return Stream<bool>.multi((controller) {
    void emit() {
      controller.add(currentUserLikedCommentIds.value.contains(commentId));
    }

    currentUserLikedCommentIds.addListener(emit);
    emit();
    controller.onCancel = () {
      currentUserLikedCommentIds.removeListener(emit);
    };
  }).distinct();
}

Stream<int> watchCommentLikeCountFromCache(SpotReviewData review) {
  return Stream<int>.multi((controller) {
    void emit() {
      controller.add(currentCommentLikeCount(review));
    }

    currentUserCommentLikeCountOverrides.addListener(emit);
    emit();
    controller.onCancel = () {
      currentUserCommentLikeCountOverrides.removeListener(emit);
    };
  }).distinct();
}

Future<void> syncCurrentUserLikedCommentsForReviews(
  List<SpotReviewData> visibleReviews,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';
  if (uid.isEmpty || visibleReviews.isEmpty) {
    return;
  }

  final visibleReviewIds = visibleReviews
      .map((review) => review.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (visibleReviewIds.isEmpty) {
    return;
  }

  final spotIds = visibleReviews
      .map((review) => review.spotId.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (spotIds.length != 1) {
    return;
  }

  try {
    await loadCurrentUserLikedCommentIdsFromLocalCache();
    final snapshot = await spotLikesCollection()
        .where('userId', isEqualTo: uid)
        .where('targetType', isEqualTo: 'comment')
        .where('commentSpotId', isEqualTo: spotIds.single)
        .limit(200)
        .debugGet(null, 'comment likes: current user visible spot page');

    final likedVisibleIds = snapshot.docs
        .map((doc) => stringFromFirebase(doc.data()['commentId'], ''))
        .where(visibleReviewIds.contains)
        .toSet();

    final nextLikedIds = {...currentUserLikedCommentIds.value}
      ..removeWhere(visibleReviewIds.contains)
      ..addAll(likedVisibleIds);

    currentUserLikedCommentIds.value = nextLikedIds;
    unawaited(saveCurrentUserLikedCommentIdsToLocalCache());
  } catch (error, stack) {
    debugPrint('Current user visible comment likes sync failed: $error');
    debugPrint('$stack');
  }
}

String spotLikeDocumentId(String spotId, String userId) {
  return '${spotId}_$userId';
}

String spotIdFromLikeDocument(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String userId,
) {
  final data = doc.data();
  final targetType = stringFromFirebase(data['targetType'], 'spot');

  if (targetType == 'comment' || data['commentId'] != null) {
    return '';
  }

  final explicitSpotId = stringFromFirebase(data['spotId'], '');
  if (explicitSpotId.isNotEmpty) {
    return explicitSpotId;
  }

  final suffix = '_$userId';
  if (doc.id.endsWith(suffix) && doc.id.length > suffix.length) {
    return doc.id.substring(0, doc.id.length - suffix.length);
  }

  return '';
}

Future<void> stopCurrentUserLikedSpotsSync() async {
  await currentUserLikedSpotsSubscription?.cancel();
  currentUserLikedSpotsSubscription = null;
  currentUserLikedSpotsSyncUid = null;
  currentUserLikedSpotsSyncStarting = false;
  currentUserLikedSpotIds.value = {};
  currentUserLikedCommentIds.value = {};
  currentUserCommentLikeCountOverrides.value = {};
}

Future<void> startCurrentUserLikedSpotsSync() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? '';

  if (uid.isEmpty) {
    await stopCurrentUserLikedSpotsSync();
    return;
  }

  if (currentUserLikedSpotsSyncUid == uid &&
      currentUserLikedSpotsSubscription != null) {
    return;
  }

  if (currentUserLikedSpotsSyncStarting &&
      currentUserLikedSpotsSyncUid == uid) {
    return;
  }

  currentUserLikedSpotsSyncStarting = true;
  currentUserLikedSpotsSyncUid = uid;

  await currentUserLikedSpotsSubscription?.cancel();
  currentUserLikedSpotsSubscription = null;
  await loadCurrentUserLikedSpotIdsFromLocalCache();

  currentUserLikedSpotsSubscription =
      trackedQuerySnapshots(
        'current user liked spots sync',
        spotLikesCollection().where('userId', isEqualTo: uid),
      ).listen(
        (snapshot) {
          final likedIds = <String>{};

          for (final doc in snapshot.docs) {
            final spotId = spotIdFromLikeDocument(doc, uid);
            if (spotId.isNotEmpty) {
              likedIds.add(spotId);
            }
          }

          currentUserLikedSpotIds.value = likedIds;
          unawaited(saveCurrentUserLikedSpotIdsToLocalCache());
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Current user liked spots sync failed: $error');
          debugPrint('$stack');
        },
      );

  currentUserLikedSpotsSyncStarting = false;
}

void setCurrentUserSpotLikedLocally(String spotId, bool liked) {
  final cleanSpotId = spotId.trim();
  if (cleanSpotId.isEmpty) {
    return;
  }

  final nextLikedIds = {...currentUserLikedSpotIds.value};
  if (liked) {
    nextLikedIds.add(cleanSpotId);
  } else {
    nextLikedIds.remove(cleanSpotId);
  }

  currentUserLikedSpotIds.value = nextLikedIds;
  unawaited(saveCurrentUserLikedSpotIdsToLocalCache());
}

Stream<bool> watchCurrentUserLikedSpotFromCache(String spotId) {
  return Stream<bool>.multi((controller) {
    void emit() {
      controller.add(currentUserLikedSpotIds.value.contains(spotId));
    }

    currentUserLikedSpotIds.addListener(emit);
    emit();
    controller.onCancel = () {
      currentUserLikedSpotIds.removeListener(emit);
    };
  }).distinct();
}

Stream<int> watchSpotLikeCount(CarSpot spot) {
  return Stream.value(spot.likeCount);
}

Stream<bool> watchCurrentUserLikedSpot(CarSpot spot) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  final spotId = spotReviewKey(spot);
  // Do not start a Firestore liked-spots listener from every spot card.
  // Cards use the locally cached liked-id set; likes/unlikes update it immediately.
  return watchCurrentUserLikedSpotFromCache(spotId);
}

Future<void> toggleSpotLike(
  BuildContext context,
  CarSpot spot,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'Log in before liking spots.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final spotId = spotReviewKey(spot);
  final likeRef = spotLikesCollection().doc(
    spotLikeDocumentId(spotId, firebaseUser.uid),
  );
  final spotRef = spot.id.trim().isEmpty
      ? null
      : spotsCollection().doc(spot.id.trim());

  final targetLiked = !currentlyLiked;
  final todayKey = localDayKey(DateTime.now());
  final toggleKey = likeRef.id;
  var likeDelta = 0;

  // Ignore rapid double taps while the first toggle is still writing. This
  // prevents accidental duplicate transactions and saves Firebase reads.
  if (!spotLikeTogglesInFlight.add(toggleKey)) {
    return;
  }

  try {
    final dailyToggleCount = await loadLocalSpotLikeDailyToggleCount(
      spotId: spotId,
      userId: firebaseUser.uid,
      dayKey: todayKey,
    );

    // Allow: like -> unlike -> like -> unlike. The next tap is blocked locally,
    // so the limit warning costs 0 Firebase reads on this device.
    if (dailyToggleCount >= maxDailySpotLikeTogglesPerUserPerSpot) {
      await showSpotLikeDailyLimitDialog(context);
      return;
    }

    setCurrentUserSpotLikedLocally(spotId, targetLiked);

    try {
      await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
        // Firestore can rerun this callback after a concurrent write.
        likeDelta = 0;
        final likeSnapshot = await transaction.debugGet(likeRef);
        DocumentSnapshot<Map<String, dynamic>>? spotSnapshot;
        if (spotRef != null) {
          spotSnapshot = await transaction.debugGet(
            spotRef,
            'spot like counter current spot get',
          );
        }

        void writeSafeSpotLikeCount(int delta, String label) {
          if (spotRef == null || spotSnapshot == null || !spotSnapshot.exists) {
            return;
          }

          final currentCount = math.max(
            0,
            intFromFirebase(spotSnapshot.data()?['likeCount'], spot.likeCount),
          );
          final nextCount = math.max(0, currentCount + delta);
          transaction.debugUpdate(spotRef, {
            'likeCount': nextCount,
            'updatedAt': FieldValue.serverTimestamp(),
          }, label);
        }

        if (targetLiked) {
          if (likeSnapshot.exists) {
            return;
          }

          transaction.debugSet(likeRef, {
            'targetType': 'spot',
            'spotId': spotId,
            'spotName': spot.name,
            'spotOwnerUid': spotNotificationOwnerUid(spot),
            'userId': firebaseUser.uid,
            'username': currentUser.username,
            'createdAt': FieldValue.serverTimestamp(),
          });
          writeSafeSpotLikeCount(1, 'spot like counter safe increment');
          likeDelta = 1;
          return;
        }

        if (!likeSnapshot.exists) {
          return;
        }

        transaction.debugDelete(likeRef);
        writeSafeSpotLikeCount(-1, 'spot like counter safe decrement');
        likeDelta = -1;
      });
    } catch (error, stack) {
      debugPrint('Spot like save failed for $spotId: $error');
      debugPrint('$stack');
      setCurrentUserSpotLikedLocally(spotId, currentlyLiked);
      if (context.mounted) {
        await showSpotLikeSaveErrorDialog(context);
      }
      return;
    }

    if (likeDelta != 0) {
      await saveLocalSpotLikeDailyToggleCount(
        spotId: spotId,
        userId: firebaseUser.uid,
        dayKey: todayKey,
        count: dailyToggleCount + 1,
      );
      updateSpotCountersLocally(spot, likeDelta: likeDelta);
    }

    if (likeDelta == 1) {
      // Do not also create the user_notifications document here. The push
      // backend creates the notification-center item for spot likes. Creating
      // one locally as well caused duplicated notifications in the app.
      try {
        final ownerUid = spotNotificationOwnerUid(spot);
        await sendPushNotificationEvent({
          'type': 'spot_like',
          'preferenceKey': 'likeNotifications',
          'notificationId': 'spot_like_${likeRef.id}',
          'likeId': likeRef.id,
          'spotId': spotId,
          'spotName': spot.name,
          if (ownerUid.isNotEmpty) 'recipientUserIds': [ownerUid],
        });
      } catch (error, stack) {
        debugPrint('Spot like notification failed: $error');
        debugPrint('$stack');
      }
    }
  } finally {
    spotLikeTogglesInFlight.remove(toggleKey);
  }
}
