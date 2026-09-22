import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show friendRequestsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show friendRequestIdFor, removeFriendship;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/profile/data/profile_fields.dart'
    show saveCurrentUserFields;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

Future<List<String>> loadCurrentUserBlockedUserIds() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return const [];
  }

  final snapshot = await usersCollection().doc(firebaseUser.uid).debugGet();
  return stringListFromFirebase(snapshot.data()?['blockedUserIds'], const []);
}

Future<bool> isUserBlockedByCurrentUser(String userId) async {
  if (userId.trim().isEmpty) {
    return false;
  }

  final blockedUserIds = await loadCurrentUserBlockedUserIds();
  return blockedUserIds.contains(userId);
}

Future<List<FriendUserData>> loadCurrentBlockedUsers() async {
  final blockedUserIds = await loadCurrentUserBlockedUserIds();
  final blockedUsers = <FriendUserData>[];

  for (final uid in blockedUserIds) {
    if (uid.trim().isEmpty) {
      continue;
    }

    try {
      final snapshot = await usersCollection().doc(uid).debugGet();
      if (snapshot.exists) {
        blockedUsers.add(FriendUserData.fromFirestore(snapshot));
      } else {
        blockedUsers.add(
          FriendUserData(
            uid: uid,
            username: 'deleted_user',
            name: trText('Profile deleted'),
            email: '',
            verified: false,
            role: UserRole.user,
            banned: false,
            deleted: true,
          ),
        );
      }
    } catch (_) {
      blockedUsers.add(
        FriendUserData(
          uid: uid,
          username: 'blocked_user',
          name: trText('Profile not found'),
          email: '',
          verified: false,
          role: UserRole.user,
          banned: false,
          deleted: false,
        ),
      );
    }
  }

  blockedUsers.sort((a, b) {
    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });

  return blockedUsers;
}

Future<void> blockUserById(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || user.uid == firebaseUser.uid) {
    return;
  }

  await saveCurrentUserFields({
    'blockedUserIds': FieldValue.arrayUnion([user.uid]),
  });

  try {
    await removeFriendship(user.uid);
  } catch (_) {}

  for (final requestId in [
    friendRequestIdFor(firebaseUser.uid, user.uid),
    friendRequestIdFor(user.uid, firebaseUser.uid),
  ]) {
    try {
      await friendRequestsCollection().doc(requestId).debugDelete();
    } catch (_) {}
  }
}

Future<void> unblockUserById(String userId) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || userId.trim().isEmpty) {
    return;
  }

  await saveCurrentUserFields({
    'blockedUserIds': FieldValue.arrayRemove([userId]),
  });
}
