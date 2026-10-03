import 'dart:math';
import 'package:ccs_app/features/auth/data/deletion_authorization.dart';
import 'package:ccs_app/core/config/app_config.dart' show telegramAuthBaseUrl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/network/json_http.dart';
import 'package:ccs_app/features/auth/data/session_lifecycle.dart';

const accountDeletionUrl = '$telegramAuthBaseUrl/api/account-deletion';
const deletionReceiptKey = 'ccs.accountDeletionReceipt';
const deletionReceiptOwnerKey = 'ccs.accountDeletionReceiptOwner';

Future<String?> accountDeletionStatus() async {
  final prefs = await SharedPreferences.getInstance();
  final receipt = prefs.getString(deletionReceiptKey);
  if (receipt == null) return null;
  final result = await postJsonToUrl(accountDeletionUrl, {
    'action': 'status',
    'receipt': receipt,
  }, logResponse: false).timeout(const Duration(seconds: 20));
  return result['status'] as String?;
}

Future<void> dismissDeletionReceipt() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(deletionReceiptKey);
  await prefs.remove(deletionReceiptOwnerKey);
}

Future<void> requestAccountDeletion() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Sign in again before deleting your account.');
  }
  final prefs = await SharedPreferences.getInstance();
  final sameAccount = prefs.getString(deletionReceiptOwnerKey) == user.uid;
  final existingReceipt = sameAccount
      ? prefs.getString(deletionReceiptKey)
      : null;
  // Recover an accepted request before refreshing a now-disabled account token.
  if (existingReceipt != null) {
    final status = await accountDeletionStatus();
    if (status == 'processing' || status == 'complete') {
      await signOutCurrentAccount();
      return;
    }
  }
  final token = await authorizeAccountDeletion(
    auth: FirebaseAuth.instance,
    user: user,
  );
  final random = Random.secure();
  final receipt =
      existingReceipt ??
      List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  // Persist before sending: a lost response must not lose the status receipt.
  // Clear the old pair first so a crash cannot attach its receipt to another UID.
  await prefs.remove(deletionReceiptKey);
  await prefs.setString(deletionReceiptOwnerKey, user.uid);
  await prefs.setString(deletionReceiptKey, receipt);
  try {
    await postJsonToUrl(
      accountDeletionUrl,
      {'confirmation': 'DELETE', 'receipt': receipt},
      headers: {'Authorization': 'Bearer $token'},
      logResponse: false,
    ).timeout(const Duration(seconds: 30));
  } catch (error) {
    String? status;
    try {
      status = await accountDeletionStatus();
    } catch (_) {
      // Preserve the original request failure when status is unavailable too.
    }
    if (status != 'processing' && status != 'complete') {
      throw StateError(accountDeletionErrorText(error));
    }
  }
  await signOutCurrentAccount();
}

String accountDeletionErrorText(Object error) {
  if (error is JsonHttpException) {
    switch (error.statusCode) {
      case 401:
        return 'Sign out and sign in again, then retry deleting your account.';
      case 503:
        return 'Account deletion is temporarily unavailable on the server. Your deletion has not been confirmed. Please try again later.';
      case 409:
        return 'A deletion request already exists for this account. Check its status on the device where you requested it.';
    }
    return 'The server could not confirm deletion (HTTP ${error.statusCode}). Please retry.';
  }
  return 'Could not confirm the deletion request. Check your connection and retry.';
}
