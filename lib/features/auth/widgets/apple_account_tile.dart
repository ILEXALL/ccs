import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:flutter/material.dart';
import 'package:ccs_app/features/auth/data/apple_auth.dart';

class AppleAccountTile extends StatefulWidget {
  const AppleAccountTile({super.key});

  @override
  State<AppleAccountTile> createState() => _AppleAccountTileState();
}

class _AppleAccountTileState extends State<AppleAccountTile> {
  bool busy = false;

  Future<void> connect() async {
    if (busy) return;
    final expectedUid = currentUser.uid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Apple to this account?'),
        content: const Text(
          'This links your Apple identity, including a private relay email if you choose one, '
          'to your existing CCS account and its Google or Telegram login. '
          'Your profile, photos, groups and progress will stay in this account.',
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
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await connectAppleToCurrentAccount(expectedUid: expectedUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apple connected. You can now use either login method for this account.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || appleAuthWasCancelled(error)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appleAuthErrorText(error))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!appleSignInAvailable) return const SizedBox.shrink();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final linked = user.uid == currentUser.uid && hasAppleProvider(user);
    return ListTile(
      leading: const Icon(Icons.apple),
      title: Text(linked ? 'Apple connected' : 'Connect Apple'),
      subtitle: Text(
        linked
            ? 'Sign in with Apple to access this same account.'
            : 'Keep your current profile when signing in with Apple.',
      ),
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: busy || linked ? null : connect,
    );
  }
}
