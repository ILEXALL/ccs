import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'admin_rewards_screen.dart' show RewardRequest;

class AdminXpGrantScreen extends StatefulWidget {
  final RewardRequest request;
  final String? Function()? currentActorId;
  final String? selectedUsername;
  final String? selectedUserId;
  const AdminXpGrantScreen({
    super.key,
    required this.request,
    this.currentActorId,
    this.selectedUsername,
    this.selectedUserId,
  });
  @override
  State<AdminXpGrantScreen> createState() => _AdminXpGrantScreenState();
}

class _AdminXpGrantScreenState extends State<AdminXpGrantScreen> {
  final username = TextEditingController();
  final amount = TextEditingController(text: '1000');
  final reason = TextEditingController();
  late final String storageKey;
  late final String? actorId;
  String? activeActor() => widget.currentActorId != null
      ? widget.currentActorId!()
      : FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic>? pending;
  bool busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    actorId = activeActor();
    storageKey = 'admin_xp_grant_pending_$actorId';
    username.text = widget.selectedUsername ?? '';
    restore();
  }

  Future<void> restore() async {
    try {
      if (actorId == null) throw StateError('Not signed in');
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      if (!mounted) return;
      if (saved != null) {
        pending = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        username.text = pending!['username'] as String;
        amount.text = '${pending!['amount']}';
        reason.text = pending!['reason'] as String;
      }
      setState(() => busy = false);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not restore the pending grant. Reopen this screen.',
        );
      }
    }
  }

  Future<void> submit() async {
    if (busy) return;
    if (activeActor() != actorId) {
      setState(() => message = 'Account changed. Reopen this screen.');
      return;
    }
    final xp = int.tryParse(amount.text.trim());
    if (xp == null ||
        xp < 1 ||
        xp > 3000 ||
        !RegExp(r'^@?[a-zA-Z0-9_]{3,30}$').hasMatch(username.text.trim()) ||
        reason.text.trim().isEmpty ||
        reason.text.trim().length > 500) {
      setState(() => message = 'Enter a username, 1–3000 XP and a reason.');
      return;
    }
    if (pending == null) {
      setState(() {
        busy = true;
        message = null;
      });
      Map<String, dynamic> target;
      try {
        target = await widget.request('admin_xp_grant_target', {
          'username': username.text.trim(),
        });
        if (!mounted) return;
        if (target['rejected'] == true) {
          setState(() {
            busy = false;
            message = '${target['message']}';
          });
          return;
        }
        if (target['userId'] is! String || target['username'] is! String) {
          throw StateError('Invalid recipient');
        }
        if (widget.selectedUserId != null &&
            target['userId'] != widget.selectedUserId) {
          setState(() {
            busy = false;
            message =
                'This username now belongs to another account. Reopen the user from Admin → Users.';
          });
          return;
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            busy = false;
            message =
                'Could not verify recipient. Check your connection and admin access.';
          });
        }
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm XP grant'),
          content: Text(
            'Add $xp XP to @${target['username']}?\n\nReason: ${reason.text.trim()}\n\nThis adds lifetime XP without using the weekly earning allowance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Grant XP'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => busy = false);
        return;
      }
      pending = {
        'username': target['username'],
        'userId': target['userId'],
        'amount': xp,
        'reason': reason.text.trim(),
        'requestId': const Uuid().v4(),
      };
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, jsonEncode(pending))) {
        throw StateError('Could not save retry details');
      }
      if (activeActor() != actorId) throw StateError('Account changed');
      final result = await widget.request('admin_xp_grant', pending!);
      if (result['rejected'] != true &&
          (result['userId'] != pending!['userId'] ||
              result['amount'] != pending!['amount'] ||
              result['xpTotal'] is! num ||
              result['level'] is! num)) {
        throw StateError('Invalid grant response');
      }
      if (!await prefs.remove(storageKey)) {
        throw StateError('Could not clear retry details');
      }
      if (!mounted) return;
      setState(() {
        message = result['rejected'] == true
            ? '${result['message']}'
            : '${result['username']}: +${result['amount']} XP. Total: ${result['xpTotal']} XP, level ${result['level']}.';
        pending = null;
        if (result['rejected'] != true) {
          username.text = widget.selectedUsername ?? '';
          reason.clear();
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Grant not confirmed. Retry this same request to check or complete it without awarding twice.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Grant XP')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Admin-only lifetime XP bonus. Weekly XP and earning limits are unchanged.',
        ),
        if (pending != null &&
            widget.selectedUserId != null &&
            pending!['userId'] != widget.selectedUserId)
          Text(
            'A previous award to @${pending!['username']} is awaiting confirmation. Resolve it before starting a new award.',
          ),
        TextField(
          controller: username,
          enabled: !busy && pending == null && widget.selectedUserId == null,
          decoration: const InputDecoration(labelText: 'Exact username'),
          autocorrect: false,
        ),
        TextField(
          controller: amount,
          enabled: !busy && pending == null,
          decoration: const InputDecoration(labelText: 'XP (1–3000)'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: reason,
          enabled: !busy && pending == null,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Reason for award',
            helperText: 'Visible to the recipient and admins',
          ),
          maxLines: 3,
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(message!),
          ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(
            busy
                ? 'Please wait…'
                : pending == null
                ? 'Grant XP'
                : 'Retry pending grant',
          ),
        ),
      ],
    ),
  );
}
