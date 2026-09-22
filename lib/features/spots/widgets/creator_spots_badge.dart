import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'package:ccs_app/features/profile/widgets/profile_info.dart'
    show MiniProfileInfoChip;
import 'package:ccs_app/features/progression/widgets/leaderboard_widgets.dart'
    show creatorSpotsText;
import 'package:ccs_app/features/spots/screens/creator_spots_screen.dart'
    show CreatorSpotsScreen, profileCountLabel;

class CreatorSpotsBadge extends StatefulWidget {
  final String uid;
  final String username;
  const CreatorSpotsBadge({
    super.key,
    required this.uid,
    required this.username,
  });

  @override
  State<CreatorSpotsBadge> createState() => _CreatorSpotsBadgeState();
}

class _CreatorSpotsBadgeState extends State<CreatorSpotsBadge>
    with LanguageReactiveState {
  late Future<int> count;

  @override
  void initState() {
    super.initState();
    count = loadCount();
  }

  @override
  void didUpdateWidget(covariant CreatorSpotsBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) count = loadCount();
  }

  Future<int> loadCount() async {
    if (widget.uid.isEmpty) return 0;
    final result = await xpScreenRequest('creator_spots', {
      'userId': widget.uid,
    });
    final value = result['count'];
    if (value is! num || value < 0) {
      throw const FormatException('Invalid created spots count');
    }
    return value.toInt();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: count,
      builder: (context, snapshot) => Semantics(
        button: true,
        label: creatorSpotsText(
          'View created spots',
          'Посмотреть созданные споты',
          'Skatīt izveidotās vietas',
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            await Navigator.push(
              context,
              appPageRoute(
                builder: (_) => CreatorSpotsScreen(
                  uid: widget.uid,
                  username: widget.username,
                ),
              ),
            );
            if (mounted) {
              setState(() {
                count = loadCount();
              });
            }
          },
          child: MiniProfileInfoChip(
            icon: Icons.add_location_alt,
            label: snapshot.hasData
                ? profileCountLabel(snapshot.data!, spots: true)
                : '${snapshot.hasError ? '—' : '…'} ${trText('Spots')}',
          ),
        ),
      ),
    );
  }
}
