import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show friendshipsCollection, userPresenceDocument, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show friendUidFromFriendshipData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

Future<List<String>> loadCurrentFriendUids() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return const [];
  }

  final snapshot = await friendshipsCollection()
      .where('userIds', arrayContains: firebaseUser.uid)
      .debugGet(null, 'friends: current friend uid query');

  return snapshot.docs
      .map((doc) => friendUidFromFriendshipData(doc.data(), firebaseUser.uid))
      .where((uid) => uid.trim().isNotEmpty)
      .toList();
}

Future<List<FriendUserData>> loadCurrentFriendUsers() async {
  final friendUids = await loadCurrentFriendUids();
  final friends = <FriendUserData>[];

  for (final uid in friendUids) {
    final snapshot = await usersCollection().doc(uid).debugGet();
    if (snapshot.exists) {
      var user = FriendUserData.fromFirestore(snapshot);
      try {
        final presenceSnapshot = await userPresenceDocument(
          uid,
        ).debugGet(null, 'friends: current friend presence get');
        user = user.withPresenceFromMap(presenceSnapshot.data());
      } catch (_) {}
      if (user.canAppearInUserLists) {
        friends.add(user);
      }
    }
  }

  friends.sort((a, b) {
    final onlineCompare = b.appearsOnline.toString().compareTo(
      a.appearsOnline.toString(),
    );
    if (onlineCompare != 0) {
      return onlineCompare;
    }

    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return friends;
}

Future<List<FriendUserData>> loadAllVisibleUsersForGroupInvite() async {
  final snapshot = await usersCollection()
      .limit(200)
      .debugGet(null, 'group invite: visible users query');
  final users = snapshot.docs
      .map(FriendUserData.fromFirestore)
      .where((user) => user.uid != currentUser.uid && user.canAppearInUserLists)
      .toList();

  users.sort((a, b) {
    final onlineCompare = b.appearsOnline.toString().compareTo(
      a.appearsOnline.toString(),
    );
    if (onlineCompare != 0) {
      return onlineCompare;
    }

    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });

  return users;
}
