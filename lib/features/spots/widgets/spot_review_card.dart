import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/spots/data/spot_reviews.dart'
    show deleteSpotReview, editSpotReview;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_review.dart'
    show SpotReviewData;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsAdmin;
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatShortDate;

class SpotReviewCard extends StatelessWidget {
  final CarSpot spot;
  final SpotReviewData review;
  final VoidCallback? onDeleted;

  const SpotReviewCard({
    super.key,
    required this.spot,
    required this.review,
    this.onDeleted,
  });

  Future<void> _showEditDialog(BuildContext context) async {
    final commentController = TextEditingController(text: review.comment);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const CcsText(
            'Edit comment',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MentionTextField(
                    controller: commentController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: trText('Edit your comment'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: CcsText(trText('Cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                if (commentController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const CcsText('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      return;
    }

    final newComment = commentController.text.trim();

    try {
      await editSpotReview(spot: spot, review: review, comment: newComment);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: CcsText(
              'Comment updated.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Could not update comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const CcsText(
            'Delete comment',
            style: TextStyle(color: Colors.white),
          ),
          content: const CcsText(
            'Are you sure you want to delete this comment?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const CcsText('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const CcsText('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await deleteSpotReview(spot: spot, review: review);
      onDeleted?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: CcsText(
              'Comment deleted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Could not delete comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = currentUid == review.userId;
    final canDelete = canEdit || userRoleIsAdmin(currentUser.role);

    return Container(
      width: double.infinity,
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
              Expanded(
                child: InkWell(
                  onTap: review.userId.trim().isEmpty
                      ? null
                      : () => openUserProfile(
                          context,
                          uid: review.userId,
                          fallbackUsername: review.username,
                        ),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: CcsText(
                      displayUsername(review.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              CcsText(
                formatShortDate(review.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CcsText(
            review.comment,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (canEdit || canDelete) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canEdit)
                  IconButton(
                    onPressed: () => _showEditDialog(context),
                    icon: const Icon(
                      Icons.edit,
                      color: Colors.white54,
                      size: 18,
                    ),
                    tooltip: 'Edit comment',
                  ),
                if (canDelete)
                  IconButton(
                    onPressed: () => _showDeleteDialog(context),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white54,
                      size: 18,
                    ),
                    tooltip: 'Delete comment',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
