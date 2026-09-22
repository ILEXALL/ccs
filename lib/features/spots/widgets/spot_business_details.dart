import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/core/platform/external_links.dart';
import 'package:ccs_app/features/spots/models/spot_business_status.dart';

class SpotBusinessStatusCard extends StatelessWidget {
  final CarSpot spot;

  const SpotBusinessStatusCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final status = businessStatusForSpot(spot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(status.icon, color: status.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  status.title,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                CcsText(
                  status.subtitle,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotContactSection extends StatelessWidget {
  final CarSpot spot;

  const SpotContactSection({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CcsText(
          'Contacts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              if (spot.contactPhone.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.phone,
                  label: 'Phone',
                  value: spot.contactPhone,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'tel', path: spot.contactPhone.trim()),
                  ),
                ),
              if (spot.contactInstagram.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.alternate_email,
                  label: 'Instagram',
                  value: spot.contactInstagram,
                  onTap: () => launchContactUri(
                    context,
                    instagramContactUri(spot.contactInstagram),
                  ),
                ),
              if (spot.contactEmail.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: spot.contactEmail,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'mailto', path: spot.contactEmail.trim()),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SpotContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    trText(label),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CcsText(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}
