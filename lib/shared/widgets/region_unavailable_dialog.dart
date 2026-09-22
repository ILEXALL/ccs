import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;

Future<void> showRegionFeatureUnavailableDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: panelGlass,
      title: const CcsText(
        'Not available in your region',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
      content: const CcsText(
        'This feature is not yet available in your region.',
        style: TextStyle(color: Colors.white70, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const CcsText('OK'),
        ),
      ],
    ),
  );
}
