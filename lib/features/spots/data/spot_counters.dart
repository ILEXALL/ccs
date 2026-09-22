import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show ConfirmedFirestoreTransaction, FirestoreDebugTransactionExtension;
import 'package:ccs_app/features/spots/data/spot_cache.dart'
    show saveApprovedSpotsToLocalCache;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show firebaseSpotCacheBySource;
import 'package:ccs_app/features/spots/data/spot_feed_projection.dart'
    show publishFirebaseSpotCaches;
import 'package:ccs_app/features/spots/models/spot_version.dart'
    show spotCacheKey;
import 'package:ccs_app/features/spots/models/car_spot.dart';

void updateSpotLocally(CarSpot spot, CarSpot Function(CarSpot current) update) {
  var updatedSpotSources = false;

  for (final sourceEntry in firebaseSpotCacheBySource.entries.toList()) {
    var sourceChanged = false;
    final nextSource = <String, CarSpot>{};

    for (final spotEntry in sourceEntry.value.entries) {
      final shouldUpdate =
          spotEntry.key == spotCacheKey(spot) ||
          isSameSpot(spotEntry.value, spot);
      nextSource[spotEntry.key] = shouldUpdate
          ? update(spotEntry.value)
          : spotEntry.value;
      sourceChanged = sourceChanged || shouldUpdate;
    }

    if (sourceChanged) {
      firebaseSpotCacheBySource[sourceEntry.key] = nextSource;
      updatedSpotSources = true;
    }
  }

  if (updatedSpotSources) {
    publishFirebaseSpotCaches();
    unawaited(saveApprovedSpotsToLocalCache());
    return;
  }

  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? update(item) : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? update(item) : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? update(item) : item)
      .toList();
}

void updateSpotCountersLocally(
  CarSpot spot, {
  int likeDelta = 0,
  int commentDelta = 0,
}) {
  if (likeDelta == 0 && commentDelta == 0) {
    return;
  }

  updateSpotLocally(
    spot,
    (current) => spotWithCounterDelta(
      current,
      likeDelta: likeDelta,
      commentDelta: commentDelta,
    ),
  );
}

Future<void> updateSpotCountersOnServer(
  CarSpot spot, {
  int likeDelta = 0,
  int commentDelta = 0,
}) async {
  final spotId = spot.id.trim();
  if (spotId.isEmpty || (likeDelta == 0 && commentDelta == 0)) {
    return;
  }

  final spotRef = spotsCollection().doc(spotId);

  try {
    await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
      final snapshot = await transaction.debugGet(
        spotRef,
        'spot counter safe current spot get',
      );
      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final update = <Object, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (likeDelta != 0) {
        final currentLikeCount = math.max(
          0,
          intFromFirebase(data['likeCount'], spot.likeCount),
        );
        update['likeCount'] = math.max(0, currentLikeCount + likeDelta);
      }

      if (commentDelta != 0) {
        final currentCommentCount = math.max(
          0,
          intFromFirebase(data['commentCount'], spot.commentCount),
        );
        update['commentCount'] = math.max(
          0,
          currentCommentCount + commentDelta,
        );
      }

      transaction.debugUpdate(spotRef, update, 'spot counter safe update');
    });
  } catch (error, stack) {
    debugPrint('Spot counter update failed for $spotId: $error');
    debugPrint('$stack');
  }
}
