import 'package:firebase_auth/firebase_auth.dart';

/// Obtain a recent Firebase token and revoke a linked Apple grant before the
/// backend disables the account. Never persist or log Apple's one-use code.
Future<String> authorizeAccountDeletion({
  required FirebaseAuth auth,
  required User user,
}) async {
  String? appleCode;
  if (user.providerData.any((provider) => provider.providerId == 'apple.com')) {
    // Reauthenticate the existing user; signInWithProvider could switch accounts.
    final credential = await user.reauthenticateWithProvider(
      AppleAuthProvider(),
    );
    if (credential.user?.uid != user.uid) {
      throw StateError('Account confirmation did not match. Please retry.');
    }
    appleCode = credential.additionalUserInfo?.authorizationCode;
    if (appleCode == null || appleCode.trim().isEmpty) {
      throw StateError('Apple did not confirm account removal. Please retry.');
    }
  }

  if (auth.currentUser?.uid != user.uid) {
    throw StateError('Your account changed. Sign in again before deleting it.');
  }
  final result = await user.getIdTokenResult(true);
  final authTime = result.authTime;
  final token = result.token;
  if (authTime == null ||
      DateTime.now().difference(authTime) > const Duration(minutes: 5)) {
    throw StateError(
      'For your security, sign out and sign in again, then return here to delete your account.',
    );
  }
  if (token == null || token.isEmpty) {
    throw StateError('Could not confirm your session. Sign in again.');
  }
  if (auth.currentUser?.uid != user.uid) {
    throw StateError('Your account changed. Sign in again before deleting it.');
  }
  if (appleCode != null) {
    // A failed revocation must not be mistaken for a successful deletion.
    await auth.revokeTokenWithAuthorizationCode(appleCode);
  }
  return token;
}
