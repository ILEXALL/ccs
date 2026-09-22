import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugTransactionExtension;

const minProfileUsernameLength = 3;

const maxProfileUsernameLength = 30;

String cleanProfileUsername(String value) {
  return value
      .trim()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String boundedProfileUsername(String value) {
  final cleanValue = cleanProfileUsername(value);
  return cleanValue.length <= maxProfileUsernameLength
      ? cleanValue
      : cleanValue.substring(0, maxProfileUsernameLength);
}

String usernameWithSuffix(String value, String suffix) {
  final cleanValue = boundedProfileUsername(value);
  final cleanSuffix = cleanProfileUsername(suffix);
  final maxBaseLength = maxProfileUsernameLength - cleanSuffix.length - 1;
  final compactValue = cleanValue.length <= maxBaseLength
      ? cleanValue
      : cleanValue.substring(0, maxBaseLength);
  return '${compactValue}_$cleanSuffix';
}

String usernameKey(String value) {
  return cleanProfileUsername(value).toLowerCase();
}

String displayUsername(String value) {
  final cleanValue = cleanProfileUsername(value);
  if (cleanValue.isNotEmpty) {
    return cleanValue;
  }

  return value.trim().replaceAll('@', '');
}

String makeUsernameFromFirebaseUser(User user) {
  final displayName = user.displayName?.trim();
  final emailName = user.email?.split('@').first.trim();
  final rawName = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : (emailName != null && emailName.isNotEmpty)
      ? emailName
      : 'ccs_driver';
  final cleanName = boundedProfileUsername(rawName);

  return cleanName.isEmpty ? 'ccs_driver' : cleanName;
}

String providerNameForFirebaseUser(User user) {
  if (user.isAnonymous) {
    return 'telegram';
  }

  final providerIds = user.providerData.map((provider) => provider.providerId);
  if (providerIds.contains('google.com')) {
    return 'google';
  }

  return providerIds.isEmpty ? 'firebase' : providerIds.first;
}

CollectionReference<Map<String, dynamic>> usernamesCollection() {
  return FirebaseFirestore.instance.collection('usernames');
}

enum UsernameAvailability {
  unchanged,
  checking,
  available,
  taken,
  invalid,
  error,
}

Future<UsernameAvailability> checkUsernameAvailabilityForCurrentUser(
  String username, {
  required String currentUsername,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUsername = cleanProfileUsername(username);

  if (cleanUsername.length < minProfileUsernameLength ||
      cleanUsername.length > maxProfileUsernameLength) {
    return UsernameAvailability.invalid;
  }

  if (usernameKey(cleanUsername) == usernameKey(currentUsername)) {
    return UsernameAvailability.unchanged;
  }

  if (firebaseUser == null) {
    return UsernameAvailability.error;
  }

  try {
    final snapshot = await usernamesCollection()
        .doc(usernameKey(cleanUsername))
        .debugGet();

    if (!snapshot.exists) {
      return UsernameAvailability.available;
    }

    final ownerUid = snapshot.data()?['uid'] as String?;
    return ownerUid == firebaseUser.uid
        ? UsernameAvailability.unchanged
        : UsernameAvailability.taken;
  } catch (_) {
    return UsernameAvailability.error;
  }
}

String usernameAvailabilityText(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.unchanged:
      return 'This is your current nickname.';
    case UsernameAvailability.checking:
      return 'Checking nickname availability...';
    case UsernameAvailability.available:
      return 'Nickname is available.';
    case UsernameAvailability.taken:
      return 'This nickname is already taken.';
    case UsernameAvailability.invalid:
      return 'Nickname must be 3 to 30 characters.';
    case UsernameAvailability.error:
      return 'Could not check nickname availability.';
  }
}

Color usernameAvailabilityColor(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Colors.greenAccent;
    case UsernameAvailability.checking:
      return Colors.white54;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Colors.redAccent;
  }
}

IconData usernameAvailabilityIcon(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Icons.check_circle_outline;
    case UsernameAvailability.checking:
      return Icons.hourglass_empty;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Icons.error_outline;
  }
}

String fallbackUsernameSuffix(String uid) {
  return uid.length <= 6 ? uid : uid.substring(0, 6);
}

Future<String> reserveUsernameForCurrentUser({
  required String preferredUsername,
  String? previousUsername,
  bool allowFallback = false,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before changing your nickname.',
    );
  }

  final cleanPreferred = cleanProfileUsername(preferredUsername);

  if (cleanPreferred.length < minProfileUsernameLength ||
      cleanPreferred.length > maxProfileUsernameLength) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'username-invalid-length',
      message: 'Nickname must be 3 to 30 characters.',
    );
  }

  final suffix = fallbackUsernameSuffix(firebaseUser.uid);

  for (var attempt = 0; attempt < 20; attempt++) {
    final candidate = attempt == 0
        ? cleanPreferred
        : attempt == 1
        ? usernameWithSuffix(cleanPreferred, suffix)
        : usernameWithSuffix(cleanPreferred, '${suffix}_$attempt');
    final key = usernameKey(candidate);
    final usernameRef = usernamesCollection().doc(key);
    final previousKey = previousUsername == null
        ? ''
        : usernameKey(previousUsername);
    final previousRef = previousKey.isEmpty || previousKey == key
        ? null
        : usernamesCollection().doc(previousKey);

    try {
      await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
        final snapshot = await transaction.debugGet(usernameRef);
        final previousSnapshot = previousRef == null
            ? null
            : await transaction.debugGet(previousRef);
        final existingUid = snapshot.data()?['uid'] as String?;
        final previousUid = previousSnapshot?.data()?['uid'] as String?;

        if (snapshot.exists && existingUid != firebaseUser.uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'username-taken',
            message: 'This nickname is already taken.',
          );
        }

        transaction.debugSet(usernameRef, {
          'uid': firebaseUser.uid,
          'username': candidate,
          'usernameKey': key,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (previousSnapshot != null &&
            previousSnapshot.exists &&
            previousUid == firebaseUser.uid) {
          transaction.debugDelete(previousRef!);
        }
      });

      return candidate;
    } on FirebaseException catch (error) {
      if (!allowFallback || error.code != 'username-taken') {
        rethrow;
      }
    }
  }

  throw FirebaseException(
    plugin: 'cloud_firestore',
    code: 'username-taken',
    message: 'This nickname is already taken.',
  );
}
