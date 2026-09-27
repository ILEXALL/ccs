import 'package:flutter/material.dart';

class EmailSignInDialog extends StatefulWidget {
  final Future<void> Function(String email, String password) signIn;
  const EmailSignInDialog({super.key, required this.signIn});
  @override
  State<EmailSignInDialog> createState() => _EmailSignInDialogState();
}

class _EmailSignInDialogState extends State<EmailSignInDialog> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!email.text.contains('@') || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.signIn(email.text.trim(), password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not sign in. Check your email, password and connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Sign in with email'),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Signing in…' : 'Sign in'),
        ),
      ],
    ),
  );
}
