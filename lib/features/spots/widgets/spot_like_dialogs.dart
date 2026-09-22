import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;

Future<void> showSpotLikeDailyLimitDialog(BuildContext context) async {
  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: CcsText(
          trText('Daily limit reached'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: CcsText(
          trText(
            'You can like and remove your like twice per day for each spot. Try again tomorrow.',
          ),
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: CcsText(trText('OK')),
          ),
        ],
      );
    },
  );
}

Future<void> showSpotLikeSaveErrorDialog(BuildContext context) async {
  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: CcsText(
          trText('Could not save like'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: CcsText(
          trText('Please try again in a moment.'),
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: CcsText(trText('OK')),
          ),
        ],
      );
    },
  );
}
