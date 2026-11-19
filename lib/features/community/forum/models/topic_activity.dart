import 'package:ccs_app/core/firestore/firebase_values.dart';

/// A month is exactly 30 * 24 hours, independent of device DST transitions.
bool forumTopicHasRecentActivity(Map<String, dynamic> data, DateTime now) {
  final reply = timestampMillisFromFirebase(data['lastReplyAt']);
  final created = timestampMillisFromFirebase(data['createdAt']);
  final activity = reply > created ? reply : created;
  // Undated legacy records remain accessible rather than being guessed old.
  return activity <= 0 ||
      now.millisecondsSinceEpoch - activity <
          const Duration(days: 30).inMilliseconds;
}
