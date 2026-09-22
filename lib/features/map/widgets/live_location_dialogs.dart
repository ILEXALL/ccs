import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show liveLocationDisclaimerDismissedKey, liveLocationDurationChoices;

String liveLocationDurationLabel(Duration duration) {
  final hours = duration.inHours;
  if (hours == 1) {
    return trText('1 hour');
  }

  return trText('$hours hours');
}

Future<bool> showLiveLocationSharingDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final dismissed = prefs.getBool(liveLocationDisclaimerDismissedKey) == true;
  if (dismissed) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  var doNotShowAgain = false;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: panelGlass,
            title: CcsText(
              trText('Share live location?'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  trText(
                    'You are about to share your live location. People who have access to this share will be able to see you on the map until sharing expires or you stop it.',
                  ),
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setDialogState(() => doNotShowAgain = !doNotShowAgain),
                  child: Row(
                    children: [
                      Checkbox(
                        value: doNotShowAgain,
                        activeColor: blue,
                        onChanged: (value) => setDialogState(
                          () => doNotShowAgain = value == true,
                        ),
                      ),
                      Expanded(
                        child: CcsText(
                          trText("Don't show again"),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: CcsText(trText('Cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(backgroundColor: blue),
                child: const CcsText(
                  'OK',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  if (accepted == true && doNotShowAgain) {
    await prefs.setBool(liveLocationDisclaimerDismissedKey, true);
  }

  return accepted == true;
}

Future<Duration?> showLiveLocationDurationDialog(BuildContext context) async {
  if (!context.mounted) {
    return null;
  }

  return showDialog<Duration>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: CcsText(
          trText('Choose sharing duration'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: liveLocationDurationChoices.map((duration) {
            final label = liveLocationDurationLabel(duration);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, duration),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: panelGlass,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: CcsText(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: CcsText(trText('Cancel')),
          ),
        ],
      );
    },
  );
}
