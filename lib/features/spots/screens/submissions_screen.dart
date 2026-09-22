import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/spots/widgets/saved_spot_tile.dart'
    show SavedSpotTile;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class UserSubmissionsScreen extends StatelessWidget {
  const UserSubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('My Submissions'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: submittedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              CcsText(
                spots.isEmpty
                    ? 'No spots created yet.'
                    : '${spots.length} created spots.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                const EmptyStateCard(
                  icon: Icons.add_location_alt,
                  title: 'No submissions yet',
                  text: 'Created spots will appear here.',
                )
              else
                for (final spot in spots) ...[
                  SavedSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: savedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              const CcsText(
                'Saved Spots',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              CcsText(
                spots.isEmpty
                    ? 'Save approved spots from Explore, Map, or Spot pages.'
                    : '${spots.length} saved car spots.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                const EmptyStateCard(
                  icon: Icons.bookmark_border,
                  title: 'No saved spots yet',
                  text: 'Tap the bookmark on a spot to keep it here.',
                )
              else
                for (final spot in spots) ...[
                  SavedSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

Widget chatAvatarWidget(ChatThreadData chat, String currentUid) {
  final photoUrl = chat.directPhotoUrlForCurrentUser(currentUid);

  if (!chat.isGroup && isNetworkUrl(photoUrl)) {
    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person_outline, color: blue),
      ),
    );
  }

  if (chat.isGroup && isNetworkUrl(photoUrl)) {
    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.groups, color: blue),
      ),
    );
  }

  return Icon(chat.isGroup ? Icons.groups : Icons.person_outline, color: blue);
}

Tab communityTab({required Widget icon, required String label}) => Tab(
  height: 62,
  icon: icon,
  child: SizedBox(
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: CcsText(
        label,
        maxLines: 1,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ),
  ),
);
