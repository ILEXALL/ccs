import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/groups/widgets/spot_group_labels.dart'
    show SpotGroupLabels;
import 'package:ccs_app/features/map/widgets/map_marker_badges.dart'
    show VerifiedSpotBadge;
import 'package:ccs_app/features/spots/widgets/save_spot_button.dart'
    show SaveSpotButton;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show spotCountryFilters, spotFilterCountry;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show toggleSpotLike, watchCurrentUserLikedSpot;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotColorForCategory;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/widgets/comment_composer.dart'
    show SpotCommentComposerSheet;
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart'
    show spotColorForSpot;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName;
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatShortDate;

class ExploreCategoryHeader extends StatelessWidget {
  final String category;
  final int count;

  const ExploreCategoryHeader({
    super.key,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final color = spotColorForCategory(category);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CcsText(
            category,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        CcsText(
          '$count',
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class ExploreSpotCard extends StatelessWidget {
  final CarSpot spot;

  const ExploreSpotCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final categoryColor = spot.isGroupSpot
        ? Colors.cyanAccent
        : spot.isTemporary
        ? Colors.orangeAccent
        : spotColorForSpot(spot);
    final addedDateText = spot.createdAtMillis > 0
        ? 'Added ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis))}'
        : 'Added date unknown';
    final addedByText = spot.addedByUid.trim().isEmpty
        ? (spot.addedBy.trim().isEmpty
              ? 'Added by unknown'
              : 'Added by ${spot.addedBy}')
        : 'Added by ${displayUsername(spot.addedBy)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spot.isGroupSpot)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: SpotGroupLabels(spot: spot),
          ),
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
              decoration: BoxDecoration(
                color: spot.isGroupSpot
                    ? const Color(0xFF09252D)
                    : const Color(0xFF0D111A).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: categoryColor.withValues(alpha: 0.50),
                  width: 1.15,
                ),
                boxShadow: [
                  BoxShadow(
                    color: categoryColor.withValues(alpha: 0.12),
                    blurRadius: 14,
                    spreadRadius: 0.3,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SpotPhoto(
                    spot: spot,
                    width: 103,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: CcsText(
                                      spot.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.25,
                                      ),
                                    ),
                                  ),
                                  if (spot.verifiedOnly) ...[
                                    const SizedBox(width: 5),
                                    const VerifiedSpotBadge(size: 14),
                                  ],
                                  if (spotCountryFilters.value.length > 1) ...[
                                    const SizedBox(width: 5),
                                    SpotCountryFlagBadge(spot: spot),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _SpotMetaLine(
                          icon: Icons.location_on_outlined,
                          text: spot.cityCountry,
                        ),
                        const SizedBox(height: 1),
                        _SpotMetaLine(
                          icon: Icons.calendar_month_outlined,
                          text: addedDateText,
                        ),
                        const SizedBox(height: 1),
                        _SpotMetaLine(
                          icon: Icons.person_outline,
                          text: addedByText,
                        ),
                        const SizedBox(height: 2),
                        CcsText(
                          spot.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10.4,
                            height: 1.0,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ExploreSpotStatsRow(spot: spot),
                            const SizedBox(width: 7),
                            SaveSpotButton(spot: spot, compact: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SpotCountryFlagBadge extends StatelessWidget {
  final CarSpot spot;

  const SpotCountryFlagBadge({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final country = spotFilterCountry(spot);
    if (country.isEmpty) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: localizedCountryName(country),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white12),
        ),
        child: CcsText(
          countryFlagEmoji(country),
          style: const TextStyle(fontSize: 12, height: 1),
        ),
      ),
    );
  }
}

class _SpotMetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SpotMetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 12),
        const SizedBox(width: 4),
        Expanded(
          child: CcsText(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class ExploreSpotStatsRow extends StatelessWidget {
  final CarSpot spot;
  final bool overlay;

  const ExploreSpotStatsRow({
    super.key,
    required this.spot,
    this.overlay = false,
  });

  Widget simpleStat({
    required IconData icon,
    required int count,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: overlay ? 16 : 15),
        const SizedBox(width: 5),
        CcsText(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: overlay ? 12 : 12,
            fontWeight: FontWeight.w900,
            shadows: overlay
                ? const [Shadow(color: Colors.black, blurRadius: 5)]
                : null,
          ),
        ),
      ],
    );

    if (overlay) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: content,
        ),
      );
    }

    return SizedBox(
      width: 40,
      height: 30,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.42)),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget statsDivider() {
    if (overlay) {
      return const SizedBox(width: 5);
    }

    return const SizedBox(width: 7);
  }

  @override
  Widget build(BuildContext context) {
    final inactiveColor = overlay
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.white70;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<bool>(
          stream: watchCurrentUserLikedSpot(spot),
          builder: (context, likedSnapshot) {
            final liked = likedSnapshot.data ?? false;

            return simpleStat(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              count: spot.likeCount,
              color: liked ? Colors.redAccent : Colors.grey.shade500,
              onTap: () => toggleSpotLike(context, spot, liked),
            );
          },
        ),
        statsDivider(),
        simpleStat(
          icon: spot.commentCount > 0
              ? Icons.chat_bubble
              : Icons.chat_bubble_outline,
          count: spot.commentCount,
          color: inactiveColor,
          onTap: () => showSpotCommentComposer(context, spot),
        ),
      ],
    );
  }
}

Future<void> showSpotCommentComposer(BuildContext context, CarSpot spot) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: panelGlass,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) {
      return SpotCommentComposerSheet(spot: spot, messenger: messenger);
    },
  );
}
