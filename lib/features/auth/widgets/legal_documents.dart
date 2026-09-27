import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const ccsTermsVersion = '2026-09-24';
const ccsPrivacyUrl =
    'https://sites.google.com/view/community-car-spots/privacy-policy';

class LegalDocumentLinks extends StatelessWidget {
  const LegalDocumentLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TermsDocumentScreen()),
        ),
        child: const Text('Terms of Use'),
      ),
      TextButton(
        onPressed: () async {
          try {
            if (await launchUrl(
              Uri.parse(ccsPrivacyUrl),
              mode: LaunchMode.externalApplication,
            )) {
              return;
            }
          } catch (_) {
            // Keep an actionable fallback when a browser cannot be opened.
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open the privacy policy. Try again.'),
            ),
          );
        },
        child: const Text('Privacy Policy'),
      ),
    ],
  );
}

class TermsDocumentScreen extends StatefulWidget {
  const TermsDocumentScreen({super.key});

  @override
  State<TermsDocumentScreen> createState() => _TermsDocumentScreenState();
}

class _TermsDocumentScreenState extends State<TermsDocumentScreen> {
  late final document = rootBundle.loadString('assets/legal/terms.txt');

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101522),
    appBar: AppBar(title: const Text('Terms of Use')),
    body: FutureBuilder<String>(
      future: document,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load terms. Please reopen this page.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: snapshot.data!.split('\n\n').map((paragraph) {
              final heading = paragraph.startsWith('#');
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  paragraph.replaceFirst(RegExp(r'^#+\s*'), ''),
                  style: heading
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }).toList(),
          ),
        );
      },
    ),
  );
}
