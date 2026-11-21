import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show ChatTitleAvatar;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatShortDate;

class SpotDetailCompactHeader extends StatelessWidget {
  final CarSpot spot;

  const SpotDetailCompactHeader({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final hasLocation = spot.cityCountry.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 3,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: blue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
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
                  fontSize: 25,
                  letterSpacing: -.5,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
            ),
          ],
        ),
        if (spot.hasOwner) ...[
          const SizedBox(height: 8),
          SpotOwnerBadge(spot: spot),
        ],
        if (hasLocation) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                color: Colors.white.withValues(alpha: 0.55),
                size: 15,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: CcsText(
                  spot.cityCountry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class SpotDetailMetaRow extends StatefulWidget {
  final CarSpot spot;
  const SpotDetailMetaRow({super.key, required this.spot});
  @override
  State<SpotDetailMetaRow> createState() => _SpotDetailMetaRowState();
}

class _SpotDetailMetaRowState extends State<SpotDetailMetaRow> {
  late Future<String> _photo;

  Future<String> _loadPhoto() async {
    final uid = widget.spot.addedByUid.trim();
    if (uid.isEmpty) return '';
    try {
      final doc = await usersCollection().doc(uid).debugGet();
      final photo = doc.data()?['photoUrl'];
      return photo is String ? photo : '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _photo = _loadPhoto();
  }

  @override
  void didUpdateWidget(SpotDetailMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spot.addedByUid != widget.spot.addedByUid) {
      _photo = _loadPhoto();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    final username = displayUsername(spot.addedBy);
    final date = spot.createdAtMillis > 0 && !spot.isTemporary
        ? formatShortDate(
            DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis),
          )
        : '';
    return InkWell(
      onTap: spot.addedByUid.trim().isEmpty
          ? null
          : () => openUserProfile(
              context,
              uid: spot.addedByUid,
              fallbackUsername: spot.addedBy,
            ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            FutureBuilder<String>(
              future: _photo,
              builder: (context, snapshot) => ChatTitleAvatar(
                photoUrl: snapshot.data ?? '',
                title: username,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    trText('Added by'),
                    style: const TextStyle(
                      color: Color(0xFF9EAABB),
                      fontSize: 11,
                    ),
                  ),
                  CcsText(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD7E5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (date.isNotEmpty)
                    CcsText(
                      date,
                      style: const TextStyle(
                        color: Color(0xFF9EAABB),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (spot.addedByUid.trim().isNotEmpty)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFF9EAABB),
              ),
          ],
        ),
      ),
    );
  }
}

class SpotOwnerBadge extends StatelessWidget {
  final CarSpot spot;

  const SpotOwnerBadge({super.key, required this.spot});

  String get ownerLabel {
    final username = spot.ownerUsername.trim();

    if (username.isNotEmpty) {
      final handle = displayUsername(username);
      return 'Owner $handle';
    }

    return 'Owner';
  }

  @override
  Widget build(BuildContext context) {
    final badge = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: blue.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_accounts, color: blue, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: CcsText(
                ownerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (spot.ownerUid.trim().isEmpty) {
      return badge;
    }

    return InkWell(
      onTap: () => openUserProfile(
        context,
        uid: spot.ownerUid,
        fallbackUsername: spot.ownerUsername,
      ),
      borderRadius: BorderRadius.circular(999),
      child: badge,
    );
  }
}
