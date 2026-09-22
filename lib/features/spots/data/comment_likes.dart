import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show ConfirmedFirestoreTransaction, FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show
        currentCommentLikeCount,
        setCommentLikeCountLocally,
        setCurrentUserCommentLikedLocally,
        watchCommentLikeCountFromCache,
        watchCurrentUserLikedCommentFromCache;
import 'package:ccs_app/core/firestore/collections.dart'
    show spotLikesCollection, spotReviewsCollection;
import 'package:ccs_app/features/spots/models/spot_review.dart'
    show SpotReviewData;

String commentLikeDocumentId(SpotReviewData review, String userId) {
  return 'comment_${review.id}_$userId';
}

Stream<int> watchCommentLikeCount(SpotReviewData review) {
  // Avoid one Firestore listener per visible comment. The count is stored on the
  // comment document and updated locally after the user taps like/unlike.
  return watchCommentLikeCountFromCache(review);
}

Stream<bool> watchCurrentUserLikedComment(SpotReviewData review) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  // Avoid one Firestore document listener per visible comment. A single
  // per-page query populates currentUserLikedCommentIds when comments load.
  return watchCurrentUserLikedCommentFromCache(review.id);
}

Future<void> toggleCommentLike(
  BuildContext context,
  SpotReviewData review,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'Log in before liking comments.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final likeRef = spotLikesCollection().doc(
    commentLikeDocumentId(review, firebaseUser.uid),
  );
  final reviewRef = spotReviewsCollection().doc(review.id);
  final targetLiked = !currentlyLiked;
  final previousCount = currentCommentLikeCount(review);
  final nextCount = math.max(0, previousCount + (targetLiked ? 1 : -1));

  setCurrentUserCommentLikedLocally(review.id, targetLiked);
  setCommentLikeCountLocally(review.id, nextCount);

  try {
    await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
      final likeSnapshot = await transaction.debugGet(
        likeRef,
        'comment like toggle existing like get',
      );
      final reviewSnapshot = await transaction.debugGet(
        reviewRef,
        'comment like counter current review get',
      );

      void writeSafeCommentLikeCount(int delta) {
        if (!reviewSnapshot.exists) {
          return;
        }

        final currentCount = math.max(
          0,
          intFromFirebase(
            reviewSnapshot.data()?['likeCount'],
            review.likeCount,
          ),
        );
        transaction.debugUpdate(reviewRef, {
          'likeCount': math.max(0, currentCount + delta),
          'updatedAt': FieldValue.serverTimestamp(),
        }, 'comment like counter safe update');
      }

      if (targetLiked) {
        if (likeSnapshot.exists) {
          return;
        }

        transaction.debugSet(likeRef, {
          'targetType': 'comment',
          'commentId': review.id,
          'commentSpotId': review.spotId,
          'userId': firebaseUser.uid,
          'username': currentUser.username,
          'createdAt': FieldValue.serverTimestamp(),
        });
        writeSafeCommentLikeCount(1);
        return;
      }

      if (!likeSnapshot.exists) {
        return;
      }

      transaction.debugDelete(likeRef);
      writeSafeCommentLikeCount(-1);
    });
  } catch (error) {
    setCurrentUserCommentLikedLocally(review.id, currentlyLiked);
    setCommentLikeCountLocally(review.id, previousCount);

    if (context.mounted) {
      final code = error is FirebaseException ? error.code : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not update comment like: $code',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }
}
