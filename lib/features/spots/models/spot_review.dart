import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase;

class SpotReviewData {
  final String id;
  final String spotId;
  final String userId;
  final String username;
  final String comment;
  final int likeCount;
  final DateTime createdAt;

  const SpotReviewData({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.username,
    required this.comment,
    required this.likeCount,
    required this.createdAt,
  });

  factory SpotReviewData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final timestamp = data['createdAt'];

    return SpotReviewData(
      id: doc.id,
      spotId: (() {
        final v = stringFromFirebase(data['spotId'], '');
        if (v.trim().isNotEmpty) return v;
        final alt = stringFromFirebase(data['spot_id'], '');
        if (alt.trim().isNotEmpty) return alt;
        return stringFromFirebase(data['spotReviewId'], '');
      })(),
      userId: stringFromFirebase(data['userId'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      comment: stringFromFirebase(data['comment'], ''),
      likeCount: math.max(0, intFromFirebase(data['likeCount'], 0)),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
