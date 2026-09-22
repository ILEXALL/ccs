import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userNotificationsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;

Future<bool> userNotificationPreferenceEnabled(
  String userId,
  String settingName,
) async {
  if (userId.trim().isEmpty) {
    return false;
  }

  try {
    final snapshot = await usersCollection().doc(userId).debugGet();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final nestedSettings = mapFromFirebase(data['settings']);

    if (data[settingName] is bool) {
      return data[settingName] == true;
    }

    if (nestedSettings[settingName] is bool) {
      return nestedSettings[settingName] == true;
    }
  } catch (error, stack) {
    debugPrint(
      'Could not read notification setting $settingName for $userId: $error',
    );
    debugPrint('$stack');
  }

  // Missing settings are treated as enabled. This matches the app default.
  return true;
}

Future<void> createUserNotification({
  required String userId,
  required String type,
  required String title,
  required String body,
  required String settingName,
  String? notificationId,
  Map<String, Object?> extra = const {},
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUserId = userId.trim();

  if (firebaseUser == null ||
      cleanUserId.isEmpty ||
      cleanUserId == firebaseUser.uid) {
    return;
  }

  final allowed = await userNotificationPreferenceEnabled(
    cleanUserId,
    settingName,
  );
  if (!allowed) {
    debugPrint(
      'Notification skipped. userId=$cleanUserId disabled $settingName',
    );
    return;
  }

  try {
    final reference = notificationId == null || notificationId.trim().isEmpty
        ? userNotificationsCollection().doc()
        : userNotificationsCollection().doc(notificationId.trim());

    await reference.debugSet({
      'userId': cleanUserId,
      'type': type,
      'title': title,
      'body': body,
      'actorUserId': firebaseUser.uid,
      'actorUsername': currentUser.username,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    }, SetOptions(merge: true));

    // Notification count is refreshed lazily when the notification center is opened.
  } catch (error, stack) {
    debugPrint('Could not create notification center item: $error');
    debugPrint('$stack');
  }
}
