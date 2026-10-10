import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:flutter/material.dart' hide Text;
import '../models/event_date_format.dart' show formatEventDate;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
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
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatClockTime;

class UpcomingTemporarySpotsSection extends StatelessWidget {
  final Map<String, List<CarSpot>> groups;

  const UpcomingTemporarySpotsSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final totalCount = groups.values.fold<int>(
      0,
      (count, spots) => count + spots.length,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: CcsText(
                  'Events',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
              ),
              CcsText(
                '$totalCount',
                style: const TextStyle(
                  color: Color(0xFF74B7FF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    color: const Color(0xFF2684FF),
                  ),
                  const SizedBox(width: 9),
                  CcsText(
                    entry.key,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Divider(color: Colors.white12)),
                  const SizedBox(width: 10),
                  CcsText(
                    '${entry.value.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < entry.value.length; index++) ...[
              UpcomingTemporarySpotNewsCard(spot: entry.value[index]),
              if (index < entry.value.length - 1) const SizedBox(height: 12),
            ],
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
    final starts = spot.startsAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    final ends = spot.expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
    final locationAvailable = spot.isTemporaryLocationAvailableNow;
    final revealMillis = spot.effectiveShowOnMapAtMillis;
    final reveal = revealMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(revealMillis);
    final revealLabel = communityText(
      en: 'Location reveal',
      ru: 'Открытие локации',
      lv: 'Atrašanās vietas atklāšana',
    );
    final date = starts == null ? '' : formatEventDate(starts);
    final endLabel = ends == null
        ? null
        : starts != null &&
              starts.year == ends.year &&
              starts.month == ends.month &&
              starts.day == ends.day
        ? formatClockTime(ends)
        : '${formatEventDate(ends)} ${formatClockTime(ends)}';

    final posterWidth = (MediaQuery.sizeOf(context).width * .23).clamp(
      76.0,
      108.0,
    );
    return Material(
      color: const Color(0xFF111925),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF293B50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: SpotPhoto(
                  spot: spot,
                  width: posterWidth,
                  height: posterWidth * 1.3,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (starts != null) ...[
                      CcsText(
                        date,
                        style: const TextStyle(
                          color: Color(0xFF91C5FF),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 7,
                        children: [
                          CcsText(
                            formatClockTime(starts),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (endLabel != null)
                            CcsText(
                              '– $endLabel',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ] else
                      CcsText(spot.temporaryTimeLabel),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CcsText(
                            spot.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (spotCountryFilters.value.length > 1) ...[
                          const SizedBox(width: 6),
                          SpotCountryFlagBadge(spot: spot),
                        ],
                      ],
                    ),
                    if (spot.isGroupSpot) ...[
                      const SizedBox(height: 6),
                      SpotGroupLabels(spot: spot),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            locationAvailable
                                ? Icons.location_on_outlined
                                : Icons.lock_outline,
                            size: 14,
                            color: const Color(0xFF8EA6C2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: CcsText(
                            locationAvailable
                                ? spot.cityCountry
                                : reveal == null
                                ? spot.temporaryLocationAvailableAtLabel
                                : '$revealLabel – ${formatEventDate(reveal)} · ${formatClockTime(reveal)}',
                            style: const TextStyle(
                              color: Color(0xFFADB9C9),
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 31),
                child: Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
