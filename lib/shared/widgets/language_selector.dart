import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class CcsLanguageSelector extends StatelessWidget {
  const CcsLanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return PopupMenuButton<AppLanguage>(
          tooltip: trText('Language'),
          onSelected: (language) {
            unawaited(appUiPreferences.setLanguage(language));
          },
          itemBuilder: (context) => [
            for (final language in AppLanguage.values)
              PopupMenuItem<AppLanguage>(
                value: language,
                child: Row(
                  children: [
                    Icon(
                      appUiPreferences.language == language
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: blue,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    CcsText(language.name.toUpperCase()),
                  ],
                ),
              ),
          ],
          child: Container(
            width: 42,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: blue.withValues(alpha: 0.52)),
            ),
            child: CcsText(
              appUiPreferences.language.name.toUpperCase(),
              style: const TextStyle(
                color: blue,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}
