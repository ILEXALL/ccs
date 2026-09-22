import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/session_count_stream.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show friendRequestsCollection, friendshipsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show accountSignOutInProgress, currentUser;
import 'package:ccs_app/features/friends/models/friend_request.dart'
    show FriendRequestData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show createUserNotification;

bool isFirestorePermissionDenied(Object error) {
  return error is FirebaseException && error.code == 'permission-denied';
}

Future<DocumentSnapshot<Map<String, dynamic>>?> safeFriendRequestGet(
  String requestId,
) async {
  try {
    return await friendRequestsCollection().doc(requestId).debugGet();
  } catch (error) {
    if (isFirestorePermissionDenied(error)) {
      return null;
    }

    rethrow;
  }
}

SessionCountStream? _incomingFriendRequests;

String? _incomingFriendRequestUid;

Future<void> stopIncomingFriendRequestCountStream() async {
  final previous = _incomingFriendRequests;
  _incomingFriendRequests = null;
  _incomingFriendRequestUid = null;
  await previous?.dispose();
}

Stream<int> incomingFriendRequestCountStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || accountSignOutInProgress) return Stream.value(0);
  if (_incomingFriendRequestUid != uid || _incomingFriendRequests == null) {
    unawaited(stopIncomingFriendRequestCountStream());
    _incomingFriendRequestUid = uid;
    _incomingFriendRequests = SessionCountStream(
      () => friendRequestsCollection()
          .where('toUid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .debugSnapshots('friends: incoming request badge listener')
          .map((snapshot) => snapshot.docs.length),
    );
  }
  return _incomingFriendRequests!.stream;
}

String friendshipIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return '${ids[0]}_${ids[1]}';
}

String friendRequestIdFor(String fromUid, String toUid) {
  return '${fromUid}_$toUid';
}

Future<bool> areUsersFriends(String firstUid, String secondUid) async {
  if (firstUid.trim().isEmpty || secondUid.trim().isEmpty) {
    return false;
  }

  try {
    final snapshot = await friendshipsCollection()
        .doc(friendshipIdFor(firstUid, secondUid))
        .debugGet();
    return snapshot.exists;
  } catch (error) {
    if (isFirestorePermissionDenied(error)) {
      return false;
    }

    rethrow;
  }
}

Future<String?> pendingRequestStatusBetweenUsers(
  String firstUid,
  String secondUid,
) async {
  final outgoing = await safeFriendRequestGet(
    friendRequestIdFor(firstUid, secondUid),
  );

  if (outgoing != null &&
      outgoing.exists &&
      outgoing.data()?['status'] == 'pending') {
    return 'outgoing';
  }

  final incoming = await safeFriendRequestGet(
    friendRequestIdFor(secondUid, firstUid),
  );

  if (incoming != null &&
      incoming.exists &&
      incoming.data()?['status'] == 'pending') {
    return 'incoming';
  }

  return null;
}

Future<void> sendFriendRequestToUser(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before adding friends.',
    );
  }

  if (user.uid == firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'cannot-add-yourself',
      message: 'You cannot add yourself as a friend.',
    );
  }

  if (await areUsersFriends(firebaseUser.uid, user.uid)) {
    return;
  }

  final incomingRef = friendRequestsCollection().doc(
    friendRequestIdFor(user.uid, firebaseUser.uid),
  );
  final incoming = await safeFriendRequestGet(incomingRef.id);

  if (incoming != null &&
      incoming.exists &&
      incoming.data()?['status'] == 'pending') {
    await acceptFriendRequest(FriendRequestData.fromFirestore(incoming));
    return;
  }

  final requestId = friendRequestIdFor(firebaseUser.uid, user.uid);
  final outgoingRef = friendRequestsCollection().doc(requestId);
  final outgoing = await safeFriendRequestGet(outgoingRef.id);
  if (outgoing != null &&
      outgoing.exists &&
      outgoing.data()?['status'] == 'pending') {
    return;
  }
  if (outgoing != null && outgoing.exists) {
    await outgoingRef.debugDelete();
  }

  await outgoingRef.debugSet({
    'fromUid': firebaseUser.uid,
    'fromUsername': currentUser.username,
    'fromName': currentUser.name,
    'toUid': user.uid,
    'toUsername': user.username,
    'toName': user.name,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  await createUserNotification(
    userId: user.uid,
    type: 'friend_request',
    title: 'New friend request',
    body: '@${currentUser.username} sent you a friend request.',
    settingName: 'friendRequestNotifications',
    notificationId: 'friend_request_$requestId',
    extra: {
      'friendRequestId': requestId,
      'fromUid': firebaseUser.uid,
      'friendUsername': currentUser.username,
    },
  );

  await sendPushNotificationEvent({
    'type': 'friend_request',
    'notificationId': 'friend_request_$requestId',
    'friendRequestId': requestId,
    'toUid': user.uid,
    'fromUsername': currentUser.username,
  });
}

Future<void> acceptFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can accept this request.',
    );
  }

  final friendshipRef = friendshipsCollection().doc(
    friendshipIdFor(request.fromUid, request.toUid),
  );
  final requestRef = friendRequestsCollection().doc(request.id);

  await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
    transaction.debugSet(friendshipRef, {
      'userIds': [request.fromUid, request.toUid]..sort(),
      'users': {
        request.fromUid: {
          'uid': request.fromUid,
          'username': request.fromUsername,
          'name': request.fromName,
        },
        request.toUid: {
          'uid': request.toUid,
          'username': request.toUsername,
          'name': request.toName,
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    transaction.debugSet(requestRef, {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

Future<void> declineFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can decline this request.',
    );
  }

  await friendRequestsCollection().doc(request.id).debugSet({
    'status': 'declined',
    'respondedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> cancelFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.fromUid != firebaseUser.uid) {
    return;
  }

  await friendRequestsCollection().doc(request.id).debugDelete();
}

String friendUidFromFriendshipData(
  Map<String, dynamic> data,
  String currentUid,
) {
  final userIds = stringListFromFirebase(data['userIds'], const []);

  for (final uid in userIds) {
    if (uid != currentUid) {
      return uid;
    }
  }

  return '';
}

Future<void> removeFriendship(String friendUid) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  await friendshipsCollection()
      .doc(friendshipIdFor(firebaseUser.uid, friendUid))
      .debugDelete();
}

String localizedFriendActionError(Object error, String fallbackKey) {
  if (error is FirebaseException) {
    if (error.code == 'blocked-user') {
      return trText('You cannot message this user.');
    }

    if (error.code == 'permission-denied') {
      return trText(fallbackKey);
    }
  }

  return trText(fallbackKey);
}
