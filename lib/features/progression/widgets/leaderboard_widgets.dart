import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/progression/data/leaderboard.dart'
    show XpLeaderboardPeriod, xpLeaderboardPeriodLabel;
import 'package:ccs_app/features/progression/models/leaderboard_entry.dart'
    show XpLeaderboardEntry;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show formatXpValue;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;

class XpLeaderboardPeriodSelector extends StatelessWidget {
  final XpLeaderboardPeriod selectedPeriod;
  final ValueChanged<XpLeaderboardPeriod> onChanged;

  const XpLeaderboardPeriodSelector({
    super.key,
    required this.selectedPeriod,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<XpLeaderboardPeriod>(
      segments: [
        for (final period in XpLeaderboardPeriod.values)
          ButtonSegment<XpLeaderboardPeriod>(
            value: period,
            icon: Icon(
              period == XpLeaderboardPeriod.week
                  ? Icons.calendar_month_outlined
                  : Icons.emoji_events_outlined,
            ),
            label: CcsText(xpLeaderboardPeriodLabel(period)),
          ),
      ],
      selected: {selectedPeriod},
      onSelectionChanged: (value) => onChanged(value.first),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white70,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? blue : panel,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? blue
                : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class XpLeaderboardTile extends StatelessWidget {
  final XpLeaderboardEntry entry;
  final XpLeaderboardPeriod period;

  const XpLeaderboardTile({
    super.key,
    required this.entry,
    this.period = XpLeaderboardPeriod.allTime,
  });

  Color get rankColor {
    switch (entry.rank) {
      case 1:
        return const Color(0xFFFFC857);
      case 2:
        return const Color(0xFFC9D1D9);
      case 3:
        return const Color(0xFFCD7F32);
    }

    return blue;
  }

  Widget avatar() {
    final imageUrl = isNetworkUrl(entry.photoUrl)
        ? entry.photoUrl
        : isNetworkUrl(entry.avatarPath)
        ? entry.avatarPath
        : '';
    final initial = entry.displayName.trim().isEmpty
        ? 'C'
        : entry.displayName.trim()[0].toUpperCase();

    Widget fallback() {
      return Center(
        child: CcsText(
          initial,
          style: const TextStyle(
            color: blue,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.36)),
      ),
      child: ClipOval(
        child: imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podium = entry.rank <= 3;
    final highlighted = entry.rank <= 10;
    final accent = rankColor;
    Widget metric(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CcsText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: CcsText(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openUserProfile(
            context,
            uid: entry.userId,
            fallbackUsername: entry.displayName,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: panelGlass,
              gradient: highlighted
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: podium ? .16 : .09),
                        const Color(0xED11151D),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: highlighted
                    ? accent.withValues(alpha: podium ? .55 : .3)
                    : Colors.white12,
              ),
              boxShadow: podium
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 48,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (highlighted)
                            Icon(
                              podium
                                  ? Icons.emoji_events_rounded
                                  : Icons.star_rounded,
                              size: podium ? 19 : 13,
                              color: accent,
                            ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: CcsText(
                              '#${entry.rank}',
                              maxLines: 1,
                              style: TextStyle(
                                color: accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    avatar(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: CcsText(
                                  entry.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (entry.verified)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.verified_rounded,
                                    color: blue,
                                    size: 14,
                                  ),
                                ),
                            ],
                          ),
                          if (entry.locationLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            CcsText(
                              entry.locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white38,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    metric(trText('Level'), '${entry.level}', blue),
                    const SizedBox(width: 8),
                    metric(
                      trText('Total XP'),
                      formatXpValue(entry.xpTotal),
                      const Color(0xFF8CD5FF),
                    ),
                    const SizedBox(width: 8),
                    metric(
                      trText('Weekly XP'),
                      formatXpValue(entry.weeklyXp),
                      const Color(0xFFA8B3C4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool qualifiesPermanentCreatedSpot(Map<String, dynamic> data, String uid) {
  final creator = stringFromFirebase(data['addedByUid'], '');
  final owner = stringFromFirebase(data['ownerUid'], '');
  return (creator.isNotEmpty ? creator : owner) == uid &&
      data['status'] == 'approved' &&
      data['isTemporary'] != true &&
      data['deleted'] != true;
}

Query<Map<String, dynamic>> creatorSpotsQuery(
  String uid, {
  bool legacyOwner = false,
}) {
  var query = spotsCollection()
      .where('visibility', isEqualTo: 'public')
      .where(legacyOwner ? 'ownerUid' : 'addedByUid', isEqualTo: uid)
      .where('status', isEqualTo: 'approved');
  if ((legacyOwner || uid != FirebaseAuth.instance.currentUser?.uid) &&
      !currentUserCanUseVerifiedOnlySpots) {
    query = query.where('verifiedOnly', isEqualTo: false);
  }
  return query;
}

String creatorSpotsText(String en, String ru, String lv) =>
    switch (appUiPreferences.language) {
      AppLanguage.en => en,
      AppLanguage.ru => ru,
      AppLanguage.lv => lv,
    };
