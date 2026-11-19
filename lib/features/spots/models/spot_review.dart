import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show messageReactionsFromFirebase;
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
  final Map<String, String> reactions;
  final DateTime createdAt;

  const SpotReviewData({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.username,
    required this.comment,
    required this.likeCount,
    this.reactions = const {},
    required this.createdAt,
  });

  factory SpotReviewData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return SpotReviewData.fromData(doc.id, doc.data() ?? {});
  }

  factory SpotReviewData.fromData(String id, Map<String, dynamic> data) {
    final timestamp = data['createdAt'];

    return SpotReviewData(
      id: id,
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
      reactions: messageReactionsFromFirebase(data['reactions']),
      likeCount: math.max(0, intFromFirebase(data['likeCount'], 0)),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
