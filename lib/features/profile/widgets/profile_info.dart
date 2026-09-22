import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class ProfileInfoRow extends StatelessWidget {
  final String location;
  final String cars;
  final Widget spots;
  const ProfileInfoRow({
    super.key,
    required this.location,
    required this.cars,
    required this.spots,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        flex: 4,
        child: MiniProfileInfoChip(icon: Icons.location_on, label: location),
      ),
      const SizedBox(width: 5),
      Flexible(
        flex: 3,
        child: MiniProfileInfoChip(icon: Icons.directions_car, label: cars),
      ),
      const SizedBox(width: 5),
      Flexible(flex: 3, child: spots),
    ],
  );
}

class MiniProfileInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const MiniProfileInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      color: blue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: blue.withValues(alpha: 0.24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: blue, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: CcsText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ),
      ],
    ),
  );
}
