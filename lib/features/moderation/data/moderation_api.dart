import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart' show moderationActionUrl;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;

Future<Map<String, dynamic>> sendModerationAction(
  Map<String, Object?> body,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'not-logged-in',
      message: 'Log in before moderation actions.',
    );
  }

  final idToken = await firebaseUser.getIdToken();
  if (idToken == null || idToken.trim().isEmpty) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'empty-id-token',
      message: 'Could not verify this moderation action.',
    );
  }

  return postJsonToUrl(
    moderationActionUrl,
    body,
    headers: {HttpHeaders.authorizationHeader: 'Bearer $idToken'},
  );
}
