import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, timestampMillisFromFirebase;

class FriendRequestData {
  final String id;
  final String fromUid;
  final String fromUsername;
  final String fromName;
  final String toUid;
  final String toUsername;
  final String toName;
  final String status;
  final int createdAtMillis;

  const FriendRequestData({
    required this.id,
    required this.fromUid,
    required this.fromUsername,
    required this.fromName,
    required this.toUid,
    required this.toUsername,
    required this.toName,
    required this.status,
    required this.createdAtMillis,
  });

  factory FriendRequestData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return FriendRequestData(
      id: doc.id,
      fromUid: stringFromFirebase(data['fromUid'], ''),
      fromUsername: stringFromFirebase(data['fromUsername'], 'ccs_driver'),
      fromName: stringFromFirebase(data['fromName'], 'CCS Driver'),
      toUid: stringFromFirebase(data['toUid'], ''),
      toUsername: stringFromFirebase(data['toUsername'], 'ccs_driver'),
      toName: stringFromFirebase(data['toName'], 'CCS Driver'),
      status: stringFromFirebase(data['status'], 'pending'),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    );
  }
}
