import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/community/groups/widgets/spot_group_labels.dart'
    show SpotGroupLabels;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show spotCountryFilters;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/widgets/explore_spot_card.dart'
    show SpotCountryFlagBadge;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

class UpcomingTemporarySpotsSection extends StatelessWidget {
  final Map<String, List<CarSpot>> groups;

  const UpcomingTemporarySpotsSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final totalCount = groups.values.fold<int>(
      0,
      (count, spots) => count + spots.length,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign, color: Colors.orangeAccent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: CcsText(
                  'Upcoming',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              CcsText(
                '$totalCount',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final groupEntry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Row(
                children: [
                  CcsText(
                    trText(groupEntry.key),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CcsText(
                    '${groupEntry.value.length}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < groupEntry.value.length; index++) ...[
              UpcomingTemporarySpotNewsCard(spot: groupEntry.value[index]),
              if (index != groupEntry.value.length - 1)
                const SizedBox(height: 10),
            ],
            if (groupEntry != groups.entries.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class UpcomingTemporarySpotNewsCard extends StatelessWidget {
  final CarSpot spot;

  const UpcomingTemporarySpotNewsCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final accent = spot.isGroupSpot ? Colors.cyanAccent : Colors.orangeAccent;
    final startsAt = spot.startsAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    final endsAt = spot.expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
    final timeWindow = startsAt == null || endsAt == null
        ? spot.temporaryTimeLabel
        : '${formatShortDateTime(startsAt)} - ${formatShortDateTime(endsAt)}';
    final description = spot.description.trim();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: spot.isGroupSpot
              ? const Color(0xFF09252D)
              : Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: spot.isGroupSpot
                ? accent.withValues(alpha: 0.5)
                : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.65),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.16),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                SpotPhoto(
                  spot: spot,
                  width: 52,
                  height: 44,
                  borderRadius: BorderRadius.circular(12),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (spot.isGroupSpot) ...[
                    SpotGroupLabels(spot: spot),
                    const SizedBox(height: 4),
                  ],
                  CcsText(
                    spot.temporaryTodayLabel,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: CcsText(
                          spot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (spotCountryFilters.value.length > 1) ...[
                        const SizedBox(width: 6),
                        SpotCountryFlagBadge(spot: spot),
                      ],
                    ],
                  ),
                  if (spot.isTemporaryLocationAvailableNow) ...[
                    const SizedBox(height: 2),
                    CcsText(
                      spot.cityCountry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  CcsText(
                    timeWindow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    CcsText(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (!spot.isTemporaryLocationAvailableNow) ...[
                    const SizedBox(height: 2),
                    CcsText(
                      spot.temporaryLocationAvailableAtLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
