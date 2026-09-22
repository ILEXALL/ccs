import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show adminNotificationsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/moderation/data/staff_recipients.dart'
    show adminUserIdsExcept;
import 'package:ccs_app/features/spots/data/spot_mutations.dart'
    show deleteSpotFromFirebase;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/models/user_role.dart'
    show userRoleIsAdmin, userRoleIsModerator;

Future<bool> confirmDeleteSpot(BuildContext context, CarSpot spot) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: const CcsText('Delete spot?'),
        content: CcsText(
          'This will remove "${spot.name}" from Firebase.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const CcsText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const CcsText(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

void showAdminActionError(
  BuildContext context, {
  required String message,
  required Object error,
}) {
  if (!context.mounted) {
    return;
  }

  final code = error is FirebaseException ? error.code : error.toString();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.redAccent,
      content: CcsText(
        '$message: $code',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

Future<String?> askSpotRemovalRequestReason(
  BuildContext context,
  CarSpot spot,
) async {
  var reason = '';

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSubmit = reason.trim().isNotEmpty;

          return AlertDialog(
            backgroundColor: panelGlass,
            title: const CcsText('Request spot removal'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  'Explain why "${spot.name}" should be removed. An admin will review your request.',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                TextField(
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (value) {
                    reason = value;
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Write the removal reason',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: blue, width: 1.4),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const CcsText('Cancel'),
              ),
              TextButton(
                onPressed: !canSubmit
                    ? null
                    : () => Navigator.pop(dialogContext, reason.trim()),
                child: const CcsText('Submit'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> requestSpotRemovalFromAdmins(
  BuildContext context,
  CarSpot spot,
) async {
  if (!userRoleIsModerator(currentUser.role)) {
    return;
  }

  if (!currentUserCanModerateSpot(spot)) {
    showAdminActionError(
      context,
      message: trText('This spot is outside your assigned countries'),
      error: 'regional-moderator-scope',
    );
    return;
  }

  final reason = await askSpotRemovalRequestReason(context, spot);
  if (reason == null || reason.trim().isEmpty) {
    return;
  }

  final senderUid =
      FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid.trim();
  final adminUids = await adminUserIdsExcept(excludedUid: senderUid);

  if (adminUids.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'No admin account is available to receive this request.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final cleanReason = reason.trim();
  final notificationBaseId = 'spot_removal_${spot.id}_${senderUid}_$nowMillis';

  try {
    final batch = FirebaseFirestore.instance.batch();

    for (final adminUid in adminUids) {
      batch.debugSet(
        adminNotificationsCollection().doc('${notificationBaseId}_$adminUid'),
        {
          'userId': adminUid,
          'type': 'spot_removal_request',
          'title': 'Spot removal request',
          'body':
              '@${displayUsername(currentUser.username)} requested removal of ${spot.name}. Reason: $cleanReason',
          'actorUserId': senderUid,
          'actorUsername': currentUser.username,
          'spotId': spot.id,
          'spotName': spot.name,
          'cityCountry': spot.cityCountry,
          'countryCode': spot.effectiveCountryCode,
          'addedBy': spot.addedBy,
          'addedByUid': spot.addedByUid,
          'reason': cleanReason,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMillis': nowMillis,
        },
        SetOptions(merge: true),
        'admin notifications: spot removal request',
      );
    }

    await batch.debugCommit();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.green,
        content: CcsText(
          'Removal request sent to admins.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  } catch (error) {
    showAdminActionError(
      context,
      message: 'Could not send removal request',
      error: error,
    );
  }
}

Future<void> deleteAdminSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterDelete = false,
}) async {
  if (userRoleIsModerator(currentUser.role)) {
    await requestSpotRemovalFromAdmins(context, spot);
    return;
  }

  if (!userRoleIsAdmin(currentUser.role)) {
    showAdminActionError(
      context,
      message: 'Only admins can delete spots directly',
      error: 'admin-only',
    );
    return;
  }

  final confirmed = await confirmDeleteSpot(context, spot);

  if (!confirmed) {
    return;
  }

  try {
    await deleteSpotFromFirebase(spot);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'Spot deleted.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (popAfterDelete) {
      Navigator.pop(context);
    }
  } catch (error) {
    showAdminActionError(
      context,
      message: 'Could not delete spot',
      error: error,
    );
  }
}
