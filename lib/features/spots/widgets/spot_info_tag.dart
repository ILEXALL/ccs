import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class SpotInfoTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  final bool fullLabel;
  const SpotInfoTag({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.fullLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: fullLabel
                    ? MediaQuery.sizeOf(context).width - 95
                    : 98,
              ),
              child: CcsText(
                label,
                maxLines: fullLabel ? null : 1,
                softWrap: fullLabel,
                overflow: fullLabel
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent.computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
