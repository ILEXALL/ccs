import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;

enum CreationKind { spot, event, privateEvent }

Future<CreationKind?> showCreationMenu(BuildContext context) =>
    showModalBottomSheet<CreationKind>(
      context: context,
      showDragHandle: true,
      backgroundColor: panelGlass,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined, color: blue),
              title: CcsText(trText('Add Spot')),
              onTap: () => Navigator.pop(context, CreationKind.spot),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined, color: blue),
              title: CcsText(trText('Add Event')),
              onTap: () => Navigator.pop(context, CreationKind.event),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: blue),
              title: CcsText(trText('Add Private Event')),
              onTap: () => Navigator.pop(context, CreationKind.privateEvent),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
