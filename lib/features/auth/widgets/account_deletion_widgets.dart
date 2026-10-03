import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/account_deletion.dart';

class DeleteAccountTile extends StatefulWidget {
  final Future<void> Function() requestDeletion;
  const DeleteAccountTile({
    super.key,
    this.requestDeletion = requestAccountDeletion,
  });
  @override
  State<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends State<DeleteAccountTile> {
  bool busy = false;
  Future<void> remove() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: const Text(
          'Your profile, garage, photos, messages, posts, spots and other account data will be removed. You will leave your groups; groups with other members will remain. This cannot be undone. Deletion continues automatically after you close the app. You can check its progress on the sign-in screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete my account',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.requestDeletion();
    } catch (error) {
      if (error is FirebaseAuthException &&
          const {
            'canceled',
            'cancelled',
            'user-cancelled',
            'web-context-canceled',
            'web-context-cancelled',
          }.contains(error.code)) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accountDeletionErrorText(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
    title: Text(
      busy ? 'Requesting deletion…' : 'Delete account',
      style: const TextStyle(color: Colors.redAccent),
    ),
    onTap: busy ? null : remove,
  );
}

class AccountDeletionStatus extends StatefulWidget {
  final Future<String?> Function() loadStatus;
  const AccountDeletionStatus({
    super.key,
    this.loadStatus = accountDeletionStatus,
  });
  @override
  State<AccountDeletionStatus> createState() => _AccountDeletionStatusState();
}

class _AccountDeletionStatusState extends State<AccountDeletionStatus> {
  late Future<String?> status = loadStatus();
  bool refreshed = false;
  Future<String?> loadStatus() {
    final request = Future<String?>.sync(widget.loadStatus);
    // Observe immediate failures before FutureBuilder subscribes next frame.
    // The original future still delivers the error to its retry UI.
    request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: status,
    builder: (context, snapshot) {
      if (!snapshot.hasError &&
          (!snapshot.hasData || snapshot.data == 'unknown')) {
        return const SizedBox.shrink();
      }
      final complete = snapshot.data == 'complete';
      final checking = snapshot.connectionState == ConnectionState.waiting;
      return Column(
        children: [
          Text(
            complete
                ? 'Your account and associated data have been deleted.'
                : snapshot.hasError
                ? 'Could not check deletion status.'
                : refreshed && !checking
                ? 'Status checked: deletion is still processing. It continues automatically; you can close the app.'
                : 'Your account deletion is processing automatically.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: checking
                ? null
                : () async {
                    if (complete) await dismissDeletionReceipt();
                    if (mounted) {
                      setState(() {
                        refreshed = true;
                        status = loadStatus();
                      });
                    }
                  },
            child: Text(
              checking
                  ? 'Checking…'
                  : complete
                  ? 'Dismiss'
                  : 'Check deletion status',
            ),
          ),
        ],
      );
    },
  );
}
