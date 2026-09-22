import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;

class AppPage extends StatelessWidget {
  final String title;
  final String text;

  const AppPage({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CcsText(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              CcsText(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
