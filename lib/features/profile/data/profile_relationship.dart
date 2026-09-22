import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userReportsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/friends/data/blocked_users.dart'
    show isUserBlockedByCurrentUser;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show areUsersFriends, pendingRequestStatusBetweenUsers;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show createAdminUserReportNotifications;
import 'package:ccs_app/features/profile/models/public_profile.dart'
    show PublicUserProfileData;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;
import 'package:ccs_app/shared/models/user_role.dart' show roleName;

class PublicProfileRelationshipState {
  final bool isSelf;
  final bool isFriend;
  final bool outgoingRequest;
  final bool incomingRequest;
  final bool blockedByCurrentUser;

  const PublicProfileRelationshipState({
    required this.isSelf,
    this.isFriend = false,
    this.outgoingRequest = false,
    this.incomingRequest = false,
    this.blockedByCurrentUser = false,
  });
}

Future<PublicProfileRelationshipState> loadPublicProfileRelationshipState(
  String userId,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || userId.trim().isEmpty) {
    return const PublicProfileRelationshipState(isSelf: false);
  }

  final isSelf = firebaseUser.uid == userId;
  if (isSelf) {
    return const PublicProfileRelationshipState(isSelf: true);
  }

  final blockedByCurrentUser = await isUserBlockedByCurrentUser(userId);
  final isFriend = await areUsersFriends(firebaseUser.uid, userId);
  final requestStatus = await pendingRequestStatusBetweenUsers(
    firebaseUser.uid,
    userId,
  );

  return PublicProfileRelationshipState(
    isSelf: false,
    isFriend: isFriend,
    outgoingRequest: requestStatus == 'outgoing',
    incomingRequest: requestStatus == 'incoming',
    blockedByCurrentUser: blockedByCurrentUser,
  );
}

Future<void> submitUserReport({
  required PublicUserProfileData reportedUser,
  required String reason,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    throw StateError('Log in required');
  }

  final reporterUid = firebaseUser.uid.trim();
  if (reporterUid.isEmpty) {
    throw StateError('Log in required');
  }

  final cleanReason = reason.trim();
  if (cleanReason.isEmpty) {
    throw StateError('Reason is required.');
  }

  if (reportedUser.uid == reporterUid) {
    throw StateError('You cannot report your own profile.');
  }

  final reporterUsername = currentUser.uid.trim().isEmpty
      ? (firebaseUser.displayName?.trim().isNotEmpty == true
            ? firebaseUser.displayName!.trim()
            : 'ccs_driver')
      : currentUser.username;
  final reporterName = currentUser.uid.trim().isEmpty
      ? (firebaseUser.displayName ?? '')
      : currentUser.name;
  final reporterEmail = currentUser.uid.trim().isEmpty
      ? (firebaseUser.email ?? '')
      : currentUser.email;

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final reportId = '${reportedUser.uid}_${reporterUid}_$nowMillis';

  await userReportsCollection()
      .doc(reportId)
      .debugSet(
        {
          'reportedUid': reportedUser.uid,
          'reportedUsername': reportedUser.username,
          'reportedName': reportedUser.name,
          'reportedEmail': reportedUser.email,
          'reportedRole': roleName(reportedUser.role),
          'countryCode': countryIsoCode(reportedUser.country) ?? '',
          'reporterUid': reporterUid,
          'reporterUsername': reporterUsername,
          'reporterName': reporterName,
          'reporterEmail': reporterEmail,
          'reason': cleanReason,
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMillis': nowMillis,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
        'profile: submit user report',
      );

  try {
    await createAdminUserReportNotifications(
      reportId: reportId,
      reportedUser: reportedUser,
      reporterUid: reporterUid,
      reporterUsername: reporterUsername,
      reason: cleanReason,
      createdAtMillis: nowMillis,
    );
  } catch (error, stack) {
    debugPrint('Could not create user report notifications: $error');
    debugPrint('$stack');
  }
}
