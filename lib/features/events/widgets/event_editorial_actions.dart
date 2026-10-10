import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:flutter/material.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show watchCurrentUserLikedSpot, toggleSpotLike;
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/shared/media/event_video_screen.dart'
    show openEventVideo;

class EventEditorialActions extends StatelessWidget {
  const EventEditorialActions({super.key, required this.spot});
  final CarSpot spot;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFCCDCEC),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            ),
            onPressed: spot.addedByUid.isEmpty
                ? null
                : () => openUserProfile(
                    context,
                    uid: spot.addedByUid,
                    fallbackUsername: spot.addedBy,
                  ),
            icon: EventCreatorAvatar(
              key: ValueKey(spot.addedByUid),
              uid: spot.addedByUid,
            ),
            label: CcsText(
              displayUsername(spot.addedBy),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        StreamBuilder<bool>(
          stream: watchCurrentUserLikedSpot(spot),
          builder: (context, snapshot) {
            final liked = snapshot.data ?? false;
            return TextButton.icon(
              onPressed: () => toggleSpotLike(context, spot, liked),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 19,
                color: liked ? Colors.pinkAccent : const Color(0xFFAFC5DC),
              ),
              label: CcsText(
                '${spot.likeCount}',
                semanticsLabel: '${spot.likeCount} ${trText('Likes')}',
              ),
            );
          },
        ),
        if (spot.reelLink.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => openEventVideo(context, spot.reelLink),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF9BCFFF),
              minimumSize: const Size(88, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              side: const BorderSide(color: Color(0xFF325A7D)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.play_circle_outline, size: 22),
            label: CcsText(
              communityText(en: 'Video', ru: 'Видео', lv: 'Video'),
            ),
          ),
      ],
    ),
  );
}

class EventCreatorAvatar extends StatefulWidget {
  const EventCreatorAvatar({super.key, required this.uid});
  final String uid;
  @override
  State<EventCreatorAvatar> createState() => _EventCreatorAvatarState();
}

class _EventCreatorAvatarState extends State<EventCreatorAvatar> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? profile =
      widget.uid.trim().isEmpty
      ? null
      : usersCollection()
            .doc(widget.uid)
            .debugSnapshots('event creator avatar');
  Widget fallback() =>
      const Icon(Icons.person_outline, size: 21, color: Color(0xFFB8D3EE));
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: profile,
        builder: (context, snapshot) {
          final value = snapshot.data?.data()?['photoUrl'];
          final url = value is String ? value.trim() : '';
          final uri = Uri.tryParse(url);
          final valid =
              uri != null &&
              ['https', 'http'].contains(uri.scheme) &&
              uri.host.isNotEmpty;
          return Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF23374B),
              border: Border.all(color: const Color(0xFF3B5874)),
            ),
            clipBehavior: Clip.antiAlias,
            child: valid
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback(),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : fallback(),
                  )
                : fallback(),
          );
        },
      );
}
