import 'package:ccs_app/core/firestore/collections.dart'
    show spotReviewsCollection;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show localDayKey;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show safeDailyCounterPathPart;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/spots/models/spot_owner.dart'
    show spotNotificationOwnerUid;
import 'package:ccs_app/features/spots/data/spot_counters.dart'
    show updateSpotCountersLocally, updateSpotCountersOnServer;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_review.dart'
    show SpotReviewData;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsAdmin;

const Duration spotDetailSessionCacheTtl = Duration(minutes: 10);

class SpotCommentsCacheEntry {
  final List<SpotReviewData> reviews;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMoreReviews;
  final bool useFallbackQuery;
  final int cachedAtMillis;

  const SpotCommentsCacheEntry({
    required this.reviews,
    required this.lastDocument,
    required this.hasMoreReviews,
    required this.useFallbackQuery,
    required this.cachedAtMillis,
  });

  bool get isFresh {
    final ageMillis = DateTime.now().millisecondsSinceEpoch - cachedAtMillis;
    return ageMillis >= 0 &&
        ageMillis <= spotDetailSessionCacheTtl.inMilliseconds;
  }
}

final spotCommentsSessionCache = <String, SpotCommentsCacheEntry>{};

void removeSpotReviewFromSessionCache(String spotId, String reviewId) {
  final cleanSpotId = spotId.trim();
  final cleanReviewId = reviewId.trim();
  if (cleanSpotId.isEmpty || cleanReviewId.isEmpty) {
    return;
  }

  final cached = spotCommentsSessionCache[cleanSpotId];
  if (cached == null) {
    return;
  }

  final nextReviews = cached.reviews
      .where((review) => review.id != cleanReviewId)
      .toList(growable: false);
  spotCommentsSessionCache[cleanSpotId] = SpotCommentsCacheEntry(
    reviews: List<SpotReviewData>.unmodifiable(nextReviews),
    lastDocument: cached.lastDocument,
    hasMoreReviews: cached.hasMoreReviews,
    useFallbackQuery: cached.useFallbackQuery,
    cachedAtMillis: DateTime.now().millisecondsSinceEpoch,
  );
}

void addSpotReviewToSessionCache(SpotReviewData review) {
  final cleanSpotId = review.spotId.trim();
  final cleanReviewId = review.id.trim();
  if (cleanSpotId.isEmpty || cleanReviewId.isEmpty) {
    return;
  }

  final cached = spotCommentsSessionCache[cleanSpotId];
  final existingReviews = cached?.reviews ?? const <SpotReviewData>[];
  final nextReviews = <SpotReviewData>[
    review,
    ...existingReviews.where((item) => item.id != cleanReviewId),
  ];

  spotCommentsSessionCache[cleanSpotId] = SpotCommentsCacheEntry(
    reviews: List<SpotReviewData>.unmodifiable(nextReviews),
    lastDocument: cached?.lastDocument,
    hasMoreReviews: cached?.hasMoreReviews ?? true,
    useFallbackQuery: cached?.useFallbackQuery ?? false,
    cachedAtMillis: DateTime.now().millisecondsSinceEpoch,
  );
}

const int spotCommentsPageSize = 5;

const int maxDailyCommentsPerUserPerSpot = 5;

String spotCommentDailyCountDocumentId({
  required String spotId,
  required String userId,
  required String dayKey,
}) {
  return '${safeDailyCounterPathPart(spotId)}_${safeDailyCounterPathPart(userId)}_$dayKey';
}

String spotCommentLocalDailyCountKey({
  required String spotId,
  required String userId,
  required String dayKey,
}) {
  return 'spot_comment_daily_count_${spotCommentDailyCountDocumentId(spotId: spotId, userId: userId, dayKey: dayKey)}';
}

Future<int> loadLocalSpotCommentDailyCount({
  required String spotId,
  required String userId,
  required String dayKey,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(
          spotCommentLocalDailyCountKey(
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

Future<void> saveLocalSpotCommentDailyCount({
  required String spotId,
  required String userId,
  required String dayKey,
  required int count,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      spotCommentLocalDailyCountKey(
        spotId: spotId,
        userId: userId,
        dayKey: dayKey,
      ),
      count,
    );
  } catch (_) {}
}

CollectionReference<Map<String, dynamic>> spotCommentDailyCountsCollection() {
  return FirebaseFirestore.instance.collection('spot_comment_daily_counts');
}

String spotReviewActionErrorMessage(Object error, {required String fallback}) {
  if (error is FirebaseException) {
    if (error.code == 'comment-daily-limit-reached') {
      return trText('You can leave 5 comments per day on this spot.');
    }
    if (error.message != null && error.message!.trim().isNotEmpty) {
      return '${trText(fallback)} ${error.message}';
    }
    return '${trText(fallback)} ${error.code}';
  }

  return '${trText(fallback)} $error';
}

Stream<int> watchSpotCommentCount(CarSpot spot) {
  return Stream.value(spot.commentCount);
}

Future<SpotReviewData> saveSpotReview({
  required CarSpot spot,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before leaving a review.',
    );
  }

  final spotId = spotReviewKey(spot);
  final cleanComment = comment.trim();
  final now = DateTime.now();
  final dayKey = localDayKey(now);
  final reviewRef = spotReviewsCollection().doc();
  final dailyCountRef = spotCommentDailyCountsCollection().doc(
    spotCommentDailyCountDocumentId(
      spotId: spotId,
      userId: firebaseUser.uid,
      dayKey: dayKey,
    ),
  );
  final localDailyCount = await loadLocalSpotCommentDailyCount(
    spotId: spotId,
    userId: firebaseUser.uid,
    dayKey: dayKey,
  );

  if (localDailyCount >= maxDailyCommentsPerUserPerSpot) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'comment-daily-limit-reached',
      message: 'You can leave 5 comments per day on this spot.',
    );
  }

  var nextDailyCount = localDailyCount + 1;

  Future<void> writeCommentWithoutServerDailyCounter() async {
    await reviewRef.debugSet(
      {
        'spotId': spotId,
        'spotName': spot.name,
        'type': 'comment',
        'userId': firebaseUser.uid,
        'username': currentUser.username,
        'comment': cleanComment,
        'likeCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      null,
      'spot comment fallback set',
    );
  }

  try {
    await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
      final dailyCountSnapshot = await transaction.debugGet(
        dailyCountRef,
        'spot comment daily count get',
      );
      final dailyCount = dailyCountSnapshot.exists
          ? intFromFirebase(dailyCountSnapshot.data()?['count'], 0)
          : 0;

      if (dailyCount >= maxDailyCommentsPerUserPerSpot) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'comment-daily-limit-reached',
          message: 'You can leave 5 comments per day on this spot.',
        );
      }

      transaction.debugSet(reviewRef, {
        'spotId': spotId,
        'spotName': spot.name,
        'type': 'comment',
        'userId': firebaseUser.uid,
        'username': currentUser.username,
        'comment': cleanComment,
        'likeCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      nextDailyCount = dailyCount + 1;
      transaction.debugSet(dailyCountRef, {
        'spotId': spotId,
        'userId': firebaseUser.uid,
        'dayKey': dayKey,
        'count': nextDailyCount,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!dailyCountSnapshot.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  } on FirebaseException catch (error) {
    if (error.code != 'permission-denied') {
      rethrow;
    }

    await writeCommentWithoutServerDailyCounter();
  }

  unawaited(
    saveLocalSpotCommentDailyCount(
      spotId: spotId,
      userId: firebaseUser.uid,
      dayKey: dayKey,
      count: nextDailyCount,
    ),
  );

  final review = SpotReviewData(
    id: reviewRef.id,
    spotId: spotId,
    userId: firebaseUser.uid,
    username: currentUser.username,
    comment: cleanComment,
    likeCount: 0,
    createdAt: now,
  );

  addSpotReviewToSessionCache(review);
  updateSpotCountersLocally(spot, commentDelta: 1);
  unawaited(updateSpotCountersOnServer(spot, commentDelta: 1));

  try {
    // Do not also create the user_notifications document here. The push
    // backend creates the notification-center item for spot comments. Creating
    // one locally as well caused duplicated notifications in the app.
    final ownerUid = spotNotificationOwnerUid(spot);
    await sendPushNotificationEvent({
      'type': 'spot_comment',
      'preferenceKey': 'commentNotifications',
      'notificationId': 'spot_comment_${reviewRef.id}',
      'reviewId': reviewRef.id,
      'spotId': spotId,
      'spotName': spot.name,
      if (ownerUid.isNotEmpty) 'recipientUserIds': [ownerUid],
    });
  } catch (error, stack) {
    debugPrint('Spot comment notification failed: $error');
    debugPrint('$stack');
  }

  return review;
}

Future<void> editSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before editing a review.',
    );
  }

  if (firebaseUser.uid != review.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can edit only your own comments.',
    );
  }

  final cleanComment = comment.trim();
  if (cleanComment.isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'empty-comment',
      message: 'Comment cannot be empty.',
    );
  }

  await spotReviewsCollection().doc(review.id).debugUpdate({
    'comment': cleanComment,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  unawaited(
    sendPushNotificationEvent({
      'type': 'spot_comment',
      'reviewId': review.id,
      'mentionsOnly': true,
    }),
  );
}

Future<void> deleteSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before deleting a review.',
    );
  }

  final canDelete =
      firebaseUser.uid == review.userId || userRoleIsAdmin(currentUser.role);

  if (!canDelete) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can delete only your own comments.',
    );
  }

  final reviewRef = spotReviewsCollection().doc(review.id);
  final reviewSnapshot = await reviewRef.debugGet(
    const GetOptions(source: Source.server),
    'spot comment delete server verify get',
  );

  if (!reviewSnapshot.exists) {
    removeSpotReviewFromSessionCache(review.spotId, review.id);
    return;
  }

  await reviewRef.debugDelete('spot comment delete');
  removeSpotReviewFromSessionCache(review.spotId, review.id);

  if (review.comment.trim().isNotEmpty) {
    updateSpotCountersLocally(spot, commentDelta: -1);
    await updateSpotCountersOnServer(spot, commentDelta: -1);
  }
}
