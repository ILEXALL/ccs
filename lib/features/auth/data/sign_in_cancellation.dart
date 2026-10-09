import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Dismissing a provider's sign-in UI is not a login failure.
bool signInWasCancelled(Object error) {
  if (error is GoogleSignInException) {
    return error.code == GoogleSignInExceptionCode.canceled;
  }
  const codes = {
    'canceled',
    'cancelled',
    'sign_in_canceled',
    'user-cancelled',
    'web-context-canceled',
    'web-context-cancelled',
  };
  if (error is FirebaseAuthException) {
    return codes.contains(error.code.toLowerCase());
  }
  if (error is PlatformException) {
    return codes.contains(error.code.toLowerCase());
  }
  return false;
}
