import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Linking proves control of both accounts and retains the current Firebase UID.
/// Never merge accounts based on email, including Apple's private relay address.
class AppleAccountTile extends StatefulWidget {
  const AppleAccountTile({super.key});

  @override
  State<AppleAccountTile> createState() => _AppleAccountTileState();
}

class _AppleAccountTileState extends State<AppleAccountTile> {
  bool busy = false;

  Future<void> link() async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Apple to this account?'),
        content: const Text(
          'Apple sign-in will open your existing CCS profile, photos and messages. '
          'This associates your Apple identity with this account. '
          'Your Google or Telegram sign-in will keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Connect Apple'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() => busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Sign in to your existing account first.');
      }
      await user.linkWithProvider(
        AppleAuthProvider()
          ..addScope('email')
          ..addScope('name'),
      );
      await user.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Apple sign-in connected.')));
    } on FirebaseAuthException catch (error) {
      if (!mounted ||
          error.code == 'web-context-cancelled' ||
          error.code == 'canceled') {
        return;
      }
      final message = switch (error.code) {
        'credential-already-in-use' ||
        'email-already-in-use' ||
        'account-exists-with-different-credential' =>
          'This Apple identity belongs to another account. No accounts were merged. Contact support for help.',
        'requires-recent-login' =>
          'Sign out and sign in to this account again, then connect Apple.',
        _ => 'Could not connect Apple. Please try again.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect Apple. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS && !Platform.isMacOS) return const SizedBox.shrink();
    final linked =
        FirebaseAuth.instance.currentUser?.providerData.any(
          (provider) => provider.providerId == 'apple.com',
        ) ??
        false;
    return ListTile(
      leading: const Icon(Icons.apple),
      title: Text(linked ? 'Apple sign-in connected' : 'Connect Apple sign-in'),
      subtitle: const Text('Use Apple to sign in to this same CCS account.'),
      trailing: busy ? const CircularProgressIndicator() : null,
      onTap: busy || linked ? null : link,
    );
  }
}
