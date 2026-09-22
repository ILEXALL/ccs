import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show xpUserStatsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'package:ccs_app/features/progression/navigation/achievements_navigation.dart'
    show openPublicAchievements;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show
        formatXpValue,
        xpLevelFromTotal,
        xpMaxLevel,
        xpWheelAccentColorForLevel,
        xpWheelAssetForLevel,
        xpWheelBoundsByTier,
        xpWheelTierForLevel;
import 'package:ccs_app/features/progression/models/xp_stats.dart'
    show XpUserStats;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;

class XpSummaryCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onTap;

  const XpSummaryCard({super.key, required this.userId, this.onTap});

  @override
  State<XpSummaryCard> createState() => _XpSummaryCardState();
}

class _XpSummaryCardState extends State<XpSummaryCard> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  String? _subscribedUserId;

  void _subscribe(String userId) {
    if (_subscribedUserId == userId) return;
    _subscribedUserId = userId;
    _stream = xpUserStatsCollection()
        .doc(userId)
        .debugSnapshots('profile: xp user stats listener');
  }

  @override
  Widget build(BuildContext context) {
    final cleanUserId = widget.userId.trim();

    if (cleanUserId != currentUser.uid) {
      _subscribedUserId = null;
      _stream = null;
      return PublicXpSummaryCard(userId: cleanUserId, onHistory: widget.onTap);
    }

    // Keep the same listener when unrelated profile fields rebuild this card.
    _subscribe(cleanUserId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey(cleanUserId),
      stream: _stream,
      builder: (context, snapshot) {
        final doc = snapshot.data;
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final stats = doc != null && doc.exists
            ? XpUserStats.fromFirestore(doc)
            : XpUserStats.empty(cleanUserId);

        return XpSummaryContent(
          stats: stats,
          loading: loading,
          unavailable: snapshot.hasError,
          onTap: widget.onTap,
        );
      },
    );
  }
}

class PublicXpSummaryCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onHistory;
  const PublicXpSummaryCard({super.key, required this.userId, this.onHistory});
  @override
  State<PublicXpSummaryCard> createState() => _PublicXpSummaryCardState();
}

class _PublicXpSummaryCardState extends State<PublicXpSummaryCard> {
  late Future<Map<String, dynamic>> request;
  void load() {
    request = xpScreenRequest('public_xp', {
      'userId': widget.userId,
      'section': 'stats',
    });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PublicXpSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: request,
    builder: (context, snapshot) {
      final total = intFromFirebase(snapshot.data?['xpTotal'], 0);
      return Column(
        children: [
          XpSummaryContent(
            stats: XpUserStats(
              userId: widget.userId,
              xpTotal: total,
              level: xpLevelFromTotal(total),
              weeklyXp: 0,
              weeklyXpWeek: '',
              xpBlocked: false,
              xpLastTransactionId: '',
            ),
            loading: snapshot.connectionState == ConnectionState.waiting,
            unavailable: snapshot.hasError,
            onTap: widget.onHistory,
          ),
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(load),
              child: CcsText(
                achievementText(
                  appUiPreferences.language.name,
                  'Retry',
                  'Повторить',
                  'Mēģināt vēlreiz',
                ),
              ),
            ),
        ],
      );
    },
  );
}

class XpLevelWheel extends StatelessWidget {
  final int level;
  final Color accentColor;
  final bool loading;
  final double size;

  const XpLevelWheel({
    super.key,
    required this.level,
    required this.accentColor,
    this.loading = false,
    this.size = 58,
  });

  @override
  Widget build(BuildContext context) {
    final asset = xpWheelAssetForLevel(level);
    final bounds = xpWheelBoundsByTier[xpWheelTierForLevel(level)]!;
    final wheelScale = 512 / bounds.width;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.44),
            blurRadius: 18,
            spreadRadius: 1.6,
          ),
          BoxShadow(
            color: accentColor.withValues(alpha: 0.22),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            return Transform.translate(
              offset: Offset(
                (256 - bounds.center.dx) * size / bounds.width,
                (256 - bounds.center.dy) * size / bounds.height,
              ),
              child: Transform.scale(scale: wheelScale, child: child),
            );
          },
          errorBuilder: (_, _, _) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor.withValues(alpha: 0.42)),
              ),
              child: Icon(
                loading ? Icons.hourglass_top_rounded : Icons.bolt_rounded,
                color: accentColor,
                size: size * 0.48,
              ),
            );
          },
        ),
      ),
    );
  }
}

class XpSummaryContent extends StatelessWidget {
  final XpUserStats stats;
  final bool loading;
  final bool unavailable;
  final VoidCallback? onTap;

  const XpSummaryContent({
    super.key,
    required this.stats,
    required this.loading,
    required this.unavailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalLabel = loading ? '...' : '${formatXpValue(stats.xpTotal)} XP';
    final levelLabel = loading ? '...' : '${stats.level}';
    final displayedLevel = loading
        ? 1
        : stats.level.clamp(1, xpMaxLevel).toInt();
    final accentColor = stats.xpBlocked
        ? Colors.redAccent
        : xpWheelAccentColorForLevel(displayedLevel);
    final nextLabel = loading
        ? '...'
        : stats.level >= xpMaxLevel
        ? trText('Max level')
        : '${formatXpValue(stats.remainingToNextLevel)} XP';
    final footerLabel = unavailable
        ? 'XP is being calculated'
        : stats.xpBlocked
        ? 'XP locked'
        : stats.hasXp
        ? 'Next level'
        : 'No XP yet';
    final progressValue = loading || unavailable
        ? null
        : stats.progressToNextLevel;

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              XpLevelWheel(
                level: displayedLevel,
                accentColor: accentColor,
                loading: loading,
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      'Driver XP',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    CcsText(
                      'Level',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CcsText(
                    totalLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CcsText(
                    '${trText('Level')} $levelLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 8,
              backgroundColor: accentColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CcsText(
                  footerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: stats.xpBlocked ? Colors.redAccent : Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!unavailable && !stats.xpBlocked && stats.hasXp)
                CcsText(
                  nextLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          XpProfileActions(
            language: appUiPreferences.language.name,
            onAchievements: () => openPublicAchievements(context, stats.userId),
            onRewards: () => Navigator.of(context).push(
              appPageRoute(
                builder: (_) => XpRewardsScreen(
                  onOpenSpot: (id) async {
                    try {
                      final doc = await FirebaseFirestore.instance
                          .collection('spots')
                          .doc(id)
                          .get();
                      if (!context.mounted || !doc.exists) return;
                      final spot = CarSpot.fromFirestore(doc);
                      if (!canViewGroupSpot(spot)) return;
                      Navigator.of(context).push(
                        appPageRoute(
                          builder: (_) => SpotDetailScreen(spot: spot),
                        ),
                      );
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: CcsText(
                              trText('Spot is not available anymore.'),
                            ),
                          ),
                        );
                    }
                  },
                  language: appUiPreferences.language.name,
                  load: () => stats.userId == currentUser.uid
                      ? xpScreenRequest('rewards')
                      : xpScreenRequest('public_xp', {
                          'userId': stats.userId,
                          'section': 'rewards',
                        }),
                ),
              ),
            ),
            onHistory: onTap,
          ),
        ],
      ),
    );

    return card;
  }
}
