import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

bool get appleSignInAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool hasAppleProvider(User user) =>
    user.providerData.any((provider) => provider.providerId == 'apple.com');

AppleAuthProvider appleAuthProvider() => AppleAuthProvider()
  ..addScope('email')
  ..addScope('name');

// Firebase's native provider flow handles Apple's nonce and credential exchange.
// Linking must use the authenticated user, never email or a new sign-in result.
Future<void> connectAppleToCurrentAccount({
  FirebaseAuth? auth,
  String? expectedUid,
}) async {
  final session = auth ?? FirebaseAuth.instance;
  final user = session.currentUser;
  if (user == null) {
    throw StateError('Sign in to your existing CCS account first.');
  }
  final uid = user.uid;
  if (expectedUid != null && expectedUid != uid) {
    throw StateError(
      'Your session does not match this profile. Sign out and sign in again.',
    );
  }
  await user.reload();
  final refreshed = session.currentUser;
  if (refreshed == null || refreshed.uid != uid) {
    throw StateError('Your account changed. Sign in again before continuing.');
  }
  if (hasAppleProvider(refreshed)) return;
  final result = await refreshed.linkWithProvider(appleAuthProvider());
  if (result.user?.uid != user.uid || session.currentUser?.uid != user.uid) {
    throw StateError('Your account changed. Sign in again before continuing.');
  }
  await result.user!.reload();
  final linked = session.currentUser;
  if (linked == null || linked.uid != uid || !hasAppleProvider(linked)) {
    throw StateError(
      'Apple connection was not confirmed. Sign in again and retry.',
    );
  }
}

// Called only after the user confirms account deletion. Keep authorization
// codes in memory and require a successful revocation before queuing deletion.
Future<void> revokeAppleForAccountDeletion({FirebaseAuth? auth}) async {
  final session = auth ?? FirebaseAuth.instance;
  final user = session.currentUser;
  if (user == null || !hasAppleProvider(user)) return;
  final result = await user.reauthenticateWithProvider(appleAuthProvider());
  if (result.user?.uid != user.uid || session.currentUser?.uid != user.uid) {
    throw StateError('Sign in to the account you want to delete.');
  }
  final code = result.additionalUserInfo?.authorizationCode;
  if (code == null || code.isEmpty) {
    throw StateError('Apple did not confirm access. Please retry deletion.');
  }
  await session.revokeTokenWithAuthorizationCode(code);
}

bool appleAuthWasCancelled(Object error) =>
    error is FirebaseAuthException &&
    const {
      'canceled',
      'cancelled',
      'web-context-cancelled',
      'user-cancelled',
    }.contains(error.code);

String appleAuthErrorText(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
      case 'email-already-in-use':
        return 'Sign in with your existing Google, Telegram or email account, then open Settings and choose Connect Apple.';
      case 'credential-already-in-use':
        return 'This Apple account is already connected to another CCS account. Your current account has not been merged.';
      case 'requires-recent-login':
        return 'Sign out and sign in again with your existing login method, then retry Connect Apple.';
      case 'operation-not-allowed':
        return 'Apple sign-in is not available yet. Please use another login method.';
      case 'network-request-failed':
        return 'Check your connection and try Apple sign-in again.';
    }
  }
  return 'Could not complete Apple sign-in. Please try again.';
}
