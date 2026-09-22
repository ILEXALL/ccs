import 'package:cloud_firestore/cloud_firestore.dart';

CollectionReference<Map<String, dynamic>> usersCollection() {
  return FirebaseFirestore.instance.collection('users');
}

CollectionReference<Map<String, dynamic>> xpUserStatsCollection() {
  return FirebaseFirestore.instance.collection('xp_user_stats');
}

CollectionReference<Map<String, dynamic>> xpTransactionsCollection() {
  return FirebaseFirestore.instance.collection('xp_transactions');
}

CollectionReference<Map<String, dynamic>> userReportsCollection() {
  return FirebaseFirestore.instance.collection('user_reports');
}

CollectionReference<Map<String, dynamic>> userPresenceCollection() {
  return FirebaseFirestore.instance.collection('user_presence');
}

DocumentReference<Map<String, dynamic>> userPresenceDocument(String uid) {
  return userPresenceCollection().doc(uid);
}

CollectionReference<Map<String, dynamic>> deviceBansCollection() {
  return FirebaseFirestore.instance.collection('device_bans');
}

CollectionReference<Map<String, dynamic>> liveLocationsCollection() {
  return FirebaseFirestore.instance.collection('live_locations');
}

CollectionReference<Map<String, dynamic>> policeReportsCollection() {
  return FirebaseFirestore.instance.collection('police_reports');
}

CollectionReference<Map<String, dynamic>> sosReportsCollection() {
  return FirebaseFirestore.instance.collection('sos_reports');
}

CollectionReference<Map<String, dynamic>> meetNotificationsCollection() {
  return FirebaseFirestore.instance.collection('meet_notifications');
}

CollectionReference<Map<String, dynamic>> adminNotificationsCollection() {
  return FirebaseFirestore.instance.collection('admin_notifications');
}

CollectionReference<Map<String, dynamic>> userNotificationsCollection() {
  return FirebaseFirestore.instance.collection('user_notifications');
}

CollectionReference<Map<String, dynamic>> projectNewsCollection() {
  return FirebaseFirestore.instance.collection('project_news');
}

CollectionReference<Map<String, dynamic>> friendRequestsCollection() {
  return FirebaseFirestore.instance.collection('friend_requests');
}

CollectionReference<Map<String, dynamic>> friendshipsCollection() {
  return FirebaseFirestore.instance.collection('friendships');
}

CollectionReference<Map<String, dynamic>>
friendLocationNotificationsCollection() {
  return FirebaseFirestore.instance.collection('friend_location_notifications');
}

CollectionReference<Map<String, dynamic>> chatsCollection() {
  return FirebaseFirestore.instance.collection('chats');
}

CollectionReference<Map<String, dynamic>> chatMessagesCollection(
  String chatId,
) {
  return chatsCollection().doc(chatId).collection('messages');
}

CollectionReference<Map<String, dynamic>> spotsCollection() {
  return FirebaseFirestore.instance.collection('spots');
}

CollectionReference<Map<String, dynamic>> spotReviewsCollection() {
  return FirebaseFirestore.instance.collection('spot_reviews');
}

CollectionReference<Map<String, dynamic>> spotLikesCollection() {
  return FirebaseFirestore.instance.collection('spot_likes');
}
