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

/// A translucent surface unifies the feed while retaining the map texture.
/// Painted gradients avoid the cost of a full-screen backdrop blur.
class EventsFeedBackdrop extends StatelessWidget {
  final Widget child;

  const EventsFeedBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x99182332), Color(0x80101823), Color(0x660B1018)],
            stops: [0, .48, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-.9, -.85),
              radius: 1.35,
              colors: [Color(0x245F482A), Color(0x005F482A)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class UpcomingTemporarySpotsSection extends StatelessWidget {
  final Map<String, List<CarSpot>> groups;

  const UpcomingTemporarySpotsSection({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: CcsText(
              'Events',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    color: const Color(0xFFAC9670),
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
    final privateEvent = spot.isGroupSpot;
    final accent = privateEvent
        ? const Color(0xFF8BD9E5)
        : const Color(0xFFE7C580);
    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: privateEvent
          ? const [Color(0xFF17333C), Color(0xFF102129), Color(0xFF111A22)]
          : const [Color(0xFF68502A), Color(0xFF46341F), Color(0xFF2B241B)],
    );
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: accent.withValues(alpha: privateEvent ? .28 : .52),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: cardGradient),
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
                      if (privateEvent) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 12,
                              color: accent,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: CcsText(
                                communityText(
                                  en: 'Private event',
                                  ru: 'Закрытое событие',
                                  lv: 'Privāts pasākums',
                                ),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (starts != null) ...[
                        CcsText(
                          date,
                          style: TextStyle(
                            color: accent,
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
                        SpotGroupLabels(spot: spot, useChips: true),
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
                              color: accent.withValues(alpha: .8),
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
                                color: Color(0xFFCEC9BE),
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
      ),
    );
  }
}
