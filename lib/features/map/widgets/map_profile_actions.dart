import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class MapPreviewProfileActions extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onSecondary;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final bool filledSecondary;

  const MapPreviewProfileActions({
    super.key,
    required this.onOpen,
    required this.onSecondary,
    this.secondaryLabel = 'Waze',
    this.secondaryIcon = Icons.navigation,
    this.filledSecondary = true,
  });

  @override
  Widget build(BuildContext context) {
    final profileLabel = trText('Open profile');
    final routeLabel = trText(secondaryLabel);
    final textStyle =
        (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    Widget content(String label, IconData icon) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: CcsText(label, textAlign: TextAlign.center, softWrap: true),
        ),
      ],
    );

    final outlinedStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white70,
      side: const BorderSide(color: Colors.white24),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.standard,
      textStyle: textStyle,
      shape: shape,
    );
    final profile = OutlinedButton(
      onPressed: onOpen,
      style: outlinedStyle,
      child: content(profileLabel, Icons.account_circle_outlined),
    );
    final secondary = filledSecondary
        ? ElevatedButton(
            onPressed: onSecondary,
            style: ElevatedButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.standard,
              textStyle: textStyle,
              shape: shape,
            ),
            child: content(routeLabel, secondaryIcon),
          )
        : OutlinedButton(
            onPressed: onSecondary,
            style: outlinedStyle,
            child: content(routeLabel, secondaryIcon),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        double requiredWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: textStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
            maxLines: 1,
          )..layout();
          // Icon, gap, horizontal padding, plus rounding/font fallback tolerance.
          final width = painter.width.ceilToDouble() + 56;
          painter.dispose();
          return width;
        }

        final buttonWidth = math.max(
          requiredWidth(profileLabel),
          requiredWidth(routeLabel),
        );
        if (constraints.maxWidth < buttonWidth * 2 + 8) {
          // No fixed height: translated labels can wrap at large accessibility sizes.
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [profile, const SizedBox(height: 8), secondary],
          );
        }
        return Row(
          children: [
            Expanded(child: profile),
            const SizedBox(width: 8),
            Expanded(child: secondary),
          ],
        );
      },
    );
  }
}
