import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;

class AdminStatusBadge extends StatelessWidget {
  final SpotStatus status;

  const AdminStatusBadge({super.key, required this.status});

  Color get color {
    switch (status) {
      case SpotStatus.pending:
        return blue;
      case SpotStatus.approved:
        return Colors.greenAccent;
      case SpotStatus.rejected:
        return Colors.redAccent;
      case SpotStatus.edited:
        return Colors.orangeAccent;
    }
  }

  IconData get icon {
    switch (status) {
      case SpotStatus.pending:
        return Icons.hourglass_bottom;
      case SpotStatus.approved:
        return Icons.check_circle;
      case SpotStatus.rejected:
        return Icons.cancel;
      case SpotStatus.edited:
        return Icons.edit_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          CcsText(
            spotStatusName(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
