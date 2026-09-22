import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart' show xpSyncUrls;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;

Future<void> syncXpWithServer(Map<String, Object?> body) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  final idToken = await firebaseUser.getIdToken();
  if (idToken == null || idToken.trim().isEmpty) {
    return;
  }

  Object? lastError;
  StackTrace? lastStack;

  for (final url in xpSyncUrls) {
    try {
      await postJsonToUrl(
        url,
        body,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $idToken'},
      );
      return;
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
    }
  }

  debugPrint('XP sync failed: $lastError');
  if (lastStack != null) {
    debugPrint('$lastStack');
  }
}

Future<Map<String, dynamic>> xpScreenRequest(
  String action, [
  Map<String, dynamic> extra = const {},
]) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Not signed in');
  final token = await user.getIdToken();
  Object? lastError;
  for (final url in xpSyncUrls) {
    try {
      final response = await postJsonToUrl(
        url,
        {'action': action, ...extra},
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      if (response['ok'] != true) throw StateError('XP unavailable');
      return Map<String, dynamic>.from(response['result'] as Map);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? StateError('XP unavailable');
}
