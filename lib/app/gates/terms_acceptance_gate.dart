import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart'
    show DeleteAccountTile;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show signOutCurrentAccount;
import 'package:ccs_app/features/auth/widgets/legal_documents.dart';

DocumentReference<Map<String, dynamic>> _acceptanceDocument() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Sign in before accepting terms.');
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('legal_acceptances')
      .doc(ccsTermsVersion);
}

Future<bool> loadCurrentTermsAcceptance() async {
  final result = await _acceptanceDocument().get(
    const GetOptions(source: Source.server),
  );
  return result.data()?['termsVersion'] == ccsTermsVersion;
}

Future<void> saveCurrentTermsAcceptance() async {
  final document = _acceptanceDocument();
  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final existing = await transaction.get(document);
    if (existing.data()?['termsVersion'] == ccsTermsVersion) return;
    transaction.set(document, {
      'termsVersion': ccsTermsVersion,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  });
}

/// Keeps new and returning users outside the community until consent is saved.
class TermsAcceptanceGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function() loadAcceptance;
  final Future<void> Function() saveAcceptance;
  final Future<void> Function() signOut;

  const TermsAcceptanceGate({
    super.key,
    required this.child,
    this.loadAcceptance = loadCurrentTermsAcceptance,
    this.saveAcceptance = saveCurrentTermsAcceptance,
    this.signOut = signOutCurrentAccount,
  });

  @override
  State<TermsAcceptanceGate> createState() => _TermsAcceptanceGateState();
}

class _TermsAcceptanceGateState extends State<TermsAcceptanceGate> {
  bool loading = true;
  bool accepted = false;
  bool checked = false;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.loadAcceptance();
      if (!mounted) return;
      setState(() {
        accepted = value;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'Could not check your agreement. Check your connection and retry.';
      });
    }
  }

  Future<void> accept() async {
    if (!checked || saving || loading) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.saveAcceptance();
      if (!mounted) return;
      setState(() {
        accepted = true;
        saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Could not save your agreement. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (accepted) return widget.child;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xff101522),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Community rules and your content',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Before continuing, read our Terms of Use and Privacy Policy. Only share content you own or have permission to share. Your photos remain yours; you give CCS permission to display them to the audience you choose.',
                    ),
                    const LegalDocumentLinks(),
                    if (loading) const CircularProgressIndicator(),
                    if (!loading)
                      CheckboxListTile(
                        key: const ValueKey('accept-terms-checkbox'),
                        value: checked,
                        onChanged: saving
                            ? null
                            : (value) =>
                                  setState(() => checked = value ?? false),
                        title: const Text(
                          'I agree to the Terms of Use and have read the Privacy Policy.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    if (error != null) ...[
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                      TextButton(
                        onPressed: saving ? null : load,
                        child: const Text('Retry check'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loading || saving || !checked ? null : accept,
                      child: Text(saving ? 'Saving…' : 'Agree and continue'),
                    ),
                    TextButton(
                      onPressed: saving
                          ? null
                          : () async {
                              try {
                                await widget.signOut();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => error =
                                        'Could not sign out. Please retry.',
                                  );
                                }
                              }
                            },
                      child: const Text('Sign out'),
                    ),
                    if (!saving) const DeleteAccountTile(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
