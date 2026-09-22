import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;

class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 42,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: blue),
          ),
          const SizedBox(height: 14),
          CcsText(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          CcsText(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
        ],
      ),
    );
  }
}
