import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatShortDate;

class SpotDetailCompactHeader extends StatelessWidget {
  final CarSpot spot;

  const SpotDetailCompactHeader({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final hasLocation = spot.cityCountry.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CcsText(
                spot.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
            ),
            if (spot.hasOwner) ...[
              const SizedBox(width: 8),
              SpotOwnerBadge(spot: spot),
            ],
          ],
        ),
        if (hasLocation) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                color: Colors.white.withValues(alpha: 0.55),
                size: 15,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: CcsText(
                  spot.cityCountry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class SpotDetailMetaRow extends StatelessWidget {
  final CarSpot spot;

  const SpotDetailMetaRow({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final addedBy = displayUsername(spot.addedBy);
    final dateText = spot.createdAtMillis > 0
        ? formatShortDate(
            DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis),
          )
        : '';

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (dateText.isNotEmpty)
          _SpotMiniMetaChip(icon: Icons.schedule, label: dateText),
        if (addedBy.trim().isNotEmpty)
          InkWell(
            onTap: spot.addedByUid.trim().isEmpty
                ? null
                : () => openUserProfile(
                    context,
                    uid: spot.addedByUid,
                    fallbackUsername: spot.addedBy,
                  ),
            borderRadius: BorderRadius.circular(999),
            child: _SpotMiniMetaChip(
              icon: Icons.person_outline,
              label: '${trText('Added by')} $addedBy',
              accent: blue,
            ),
          ),
      ],
    );
  }
}

class _SpotMiniMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;

  const _SpotMiniMetaChip({
    required this.icon,
    required this.label,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.white54;

    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: CcsText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: accent == null ? FontWeight.w700 : FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotOwnerBadge extends StatelessWidget {
  final CarSpot spot;

  const SpotOwnerBadge({super.key, required this.spot});

  String get ownerLabel {
    final username = spot.ownerUsername.trim();

    if (username.isNotEmpty) {
      final handle = displayUsername(username);
      return 'Owner $handle';
    }

    return 'Owner';
  }

  @override
  Widget build(BuildContext context) {
    final badge = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: blue.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_accounts, color: blue, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: CcsText(
                ownerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (spot.ownerUid.trim().isEmpty) {
      return badge;
    }

    return InkWell(
      onTap: () => openUserProfile(
        context,
        uid: spot.ownerUid,
        fallbackUsername: spot.ownerUsername,
      ),
      borderRadius: BorderRadius.circular(999),
      child: badge,
    );
  }
}
