import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show spotsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/features/auth/data/account_bans.dart'
    show userBanIsActive;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show usernameKey;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show upsertSpotIntoLocalImmediateCache;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class SpotOwnerAssignment {
  final String uid;
  final String username;

  const SpotOwnerAssignment({required this.uid, required this.username});
}

bool canTransferSpotOwnership(AppUser user, {String countryCode = ''}) =>
    user.uid.isNotEmpty &&
    !user.banActive &&
    (user.role == UserRole.admin ||
        (user.role == UserRole.moderator &&
            user.moderatorCountryCodes.contains(
              countryCode.trim().toUpperCase(),
            )));

Map<String, Object?> spotOwnershipTransferFields({
  required Map<String, dynamic> spot,
  required String recipientUid,
  required Map<String, dynamic> recipient,
  required String actorUid,
}) {
  if (recipientUid.isEmpty ||
      recipient['deleted'] == true ||
      userBanIsActive(recipient)) {
    throw StateError('Choose an active user.');
  }
  final username = stringFromFirebase(recipient['username'], '').trim();
  if (username.isEmpty) throw StateError('This user has no profile nickname.');
  if (spot['addedByUid'] == recipientUid && spot['ownerUid'] == recipientUid) {
    throw StateError('This user already owns the spot.');
  }
  return {
    'addedByUid': recipientUid,
    'addedBy': username,
    'ownerUid': recipientUid,
    'ownerUsername': username,
    'ownershipTransferredFromUid': stringFromFirebase(spot['addedByUid'], ''),
    'previousBusinessOwnerUid': stringFromFirebase(spot['ownerUid'], ''),
    'ownershipTransferredByUid': actorUid,
    'ownershipTransferredAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Future<CarSpot> transferSpotOwnership(
  CarSpot expected,
  SpotOwnerAssignment recipient,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null ||
      uid != currentUser.uid ||
      !canTransferSpotOwnership(
        currentUser,
        countryCode: expected.countryCode,
      )) {
    throw StateError('Only admins and moderators can transfer ownership.');
  }
  final ref = spotsCollection().doc(expected.id);
  final updated = await FirebaseFirestore.instance.debugRunTransaction<CarSpot>(
    (transaction) async {
      final snapshot = await transaction.debugGet(
        ref,
        'ownership transfer: spot',
      );
      final target = await transaction.debugGet(
        usersCollection().doc(recipient.uid),
        'ownership transfer: recipient',
      );
      final data = snapshot.data();
      if (data == null || !target.exists) {
        throw StateError('The spot or user no longer exists.');
      }
      if (stringFromFirebase(data['addedByUid'], '') != expected.addedByUid ||
          stringFromFirebase(data['ownerUid'], '') != expected.ownerUid) {
        throw StateError('Ownership changed. Reopen the spot and try again.');
      }
      final fields = spotOwnershipTransferFields(
        spot: data,
        recipientUid: target.id,
        recipient: target.data()!,
        actorUid: uid,
      );
      transaction.debugUpdate(ref, fields, 'ownership transfer');
      return CarSpot.fromFirestore(snapshot).copyWith(
        addedByUid: target.id,
        addedBy: fields['addedBy']! as String,
        ownerUid: target.id,
        ownerUsername: fields['ownerUsername']! as String,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
    },
  );
  upsertSpotIntoLocalImmediateCache(updated);
  reviewSpots.value = reviewSpots.value
      .map((spot) => isSameSpot(spot, updated) ? updated : spot)
      .toList();
  submittedSpots.value = submittedSpots.value
      .where((spot) => !isSameSpot(spot, updated))
      .toList();
  if (updated.addedByUid == currentUser.uid) {
    submittedSpots.value = [...submittedSpots.value, updated];
  }
  return updated;
}

Future<SpotOwnerAssignment?> findSpotOwnerAssignment(
  String rawInput, {
  SpotOwnerAssignment? currentOwner,
}) async {
  final input = rawInput.trim();

  if (input.isEmpty) {
    return null;
  }

  final cleanInput = input.startsWith('@') ? input.substring(1) : input;

  if (currentOwner != null &&
      currentOwner.uid.isNotEmpty &&
      (cleanInput == currentOwner.uid ||
          usernameKey(cleanInput) == usernameKey(currentOwner.username))) {
    return currentOwner;
  }

  final byUid = await usersCollection().doc(cleanInput).debugGet();
  if (byUid.exists) {
    final data = byUid.data() ?? {};
    return SpotOwnerAssignment(
      uid: byUid.id,
      username: stringFromFirebase(data['username'], byUid.id),
    );
  }

  final byUsername = await usersCollection()
      .where('usernameKey', isEqualTo: usernameKey(cleanInput))
      .limit(1)
      .debugGet(null, 'spot owner search: username lookup');
  if (byUsername.docs.isNotEmpty) {
    final doc = byUsername.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  final byEmail = await usersCollection()
      .where('email', isEqualTo: input)
      .limit(1)
      .debugGet(null, 'spot owner search: email lookup');
  if (byEmail.docs.isNotEmpty) {
    final doc = byEmail.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  return null;
}
