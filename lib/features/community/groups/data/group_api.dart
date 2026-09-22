import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;

Future<Map<String, dynamic>> privateGroupAction(
  Map<String, Object?> body,
) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) throw StateError('Sign in first.');
  return postJsonToUrl(
    'https://ccs-telegram-auth-server.vercel.app/api/private-groups',
    body,
    headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
  ).timeout(const Duration(seconds: 30));
}
