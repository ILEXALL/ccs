import 'package:ccs_app/features/auth/data/sign_in_cancellation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  test('Google account chooser dismissal is silent', () {
    expect(
      signInWasCancelled(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: '[16] Cancelled by user.',
        ),
      ),
      isTrue,
    );
  });
  test('native and Firebase cancellation codes are silent', () {
    expect(
      signInWasCancelled(PlatformException(code: 'sign_in_canceled')),
      isTrue,
    );
    expect(
      signInWasCancelled(FirebaseAuthException(code: 'web-context-cancelled')),
      isTrue,
    );
  });
  test('real failures are not hidden by cancellation handling', () {
    expect(
      signInWasCancelled(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      ),
      isFalse,
    );
    expect(
      signInWasCancelled(FirebaseAuthException(code: 'network-request-failed')),
      isFalse,
    );
    expect(
      signInWasCancelled(PlatformException(code: 'sign_in_failed')),
      isFalse,
    );
    expect(
      signInWasCancelled(Exception('request canceled by server')),
      isFalse,
    );
  });
}
