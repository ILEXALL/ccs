import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show observedDocSnapshots;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState;
import 'package:ccs_app/features/progression/navigation/achievements_navigation.dart'
    show openPublicAchievements;

class FeaturedAchievementDisplay extends StatelessWidget {
  final Map<String, dynamic> item;
  final String language;
  final double emblemSize;
  const FeaturedAchievementDisplay({
    super.key,
    required this.item,
    required this.language,
    this.emblemSize = 64,
  });
  @override
  Widget build(BuildContext context) {
    final titles = item['title'];
    final label = titles is Map
        ? (titles[language] ??
                  titles['en'] ??
                  achievementCategoryLabel(
                    item['category']?.toString() ?? 'spots',
                    language,
                  ))
              .toString()
        : achievementCategoryLabel(
            item['category']?.toString() ?? 'spots',
            language,
          );
    return SizedBox(
      width: emblemSize + 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: emblemSize,
            height: emblemSize,
            child: FittedBox(
              fit: BoxFit.contain,
              child: AchievementBadge(item: item, displayHeight: emblemSize),
            ),
          ),
          const SizedBox(height: 4),
          CcsText(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturedProfileAchievement extends StatefulWidget {
  final String userId;
  final double emblemSize;
  const FeaturedProfileAchievement({
    super.key,
    required this.userId,
    this.emblemSize = 64,
  });
  @override
  State<FeaturedProfileAchievement> createState() =>
      _FeaturedProfileAchievementState();
}

class _FeaturedProfileAchievementState extends State<FeaturedProfileAchievement>
    with LanguageReactiveState {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  void subscribe() {
    stream = observedDocSnapshots(
      FirebaseFirestore.instance
          .collection('xp_featured_achievements')
          .doc(widget.userId),
      'profile: featured achievement',
    );
  }

  @override
  void initState() {
    super.initState();
    subscribe();
  }

  @override
  void didUpdateWidget(covariant FeaturedProfileAchievement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) subscribe();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final raw = snapshot.data?.data()?['item'];
          if (raw is! Map) return const SizedBox.shrink();
          final item = Map<String, dynamic>.from(raw)..['status'] = 'confirmed';
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: () => openPublicAchievements(context, widget.userId),
              child: FeaturedAchievementDisplay(
                item: item,
                language: appUiPreferences.language.name,
                emblemSize: widget.emblemSize,
              ),
            ),
          );
        },
      );
}
