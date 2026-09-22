import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/navigation/chat_navigation.dart'
    show openMessageToUserFromContext;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/friends/data/blocked_users.dart'
    show blockUserById, unblockUserById;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show
        acceptFriendRequest,
        friendRequestIdFor,
        localizedFriendActionError,
        removeFriendship,
        safeFriendRequestGet,
        sendFriendRequestToUser;
import 'package:ccs_app/features/friends/models/friend_request.dart'
    show FriendRequestData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanManageProfileCountry;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show showAdminActionError;
import 'package:ccs_app/features/profile/data/profile_relationship.dart'
    show
        PublicProfileRelationshipState,
        loadPublicProfileRelationshipState,
        submitUserReport;
import 'package:ccs_app/features/profile/models/public_profile.dart'
    show PublicUserProfileData;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class PublicProfileActions extends StatefulWidget {
  final PublicUserProfileData profile;

  const PublicProfileActions({super.key, required this.profile});

  @override
  State<PublicProfileActions> createState() => _PublicProfileActionsState();
}

class _PublicProfileActionsState extends State<PublicProfileActions>
    with LanguageReactiveState {
  late Future<PublicProfileRelationshipState> relationshipFuture;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    relationshipFuture = loadPublicProfileRelationshipState(widget.profile.uid);
  }

  @override
  void didUpdateWidget(PublicProfileActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid) {
      relationshipFuture = loadPublicProfileRelationshipState(
        widget.profile.uid,
      );
    }
  }

  FriendUserData get user {
    return FriendUserData(
      uid: widget.profile.uid,
      username: widget.profile.username,
      name: widget.profile.name,
      email: widget.profile.email,
      photoUrl: widget.profile.photoUrl,
      avatarPath: widget.profile.avatarPath,
      verified: widget.profile.verified,
      role: widget.profile.role,
      globalChatModerator: widget.profile.globalChatModerator,
      banned: false,
      deleted: false,
    );
  }

  void refreshRelationship() {
    if (!mounted) {
      return;
    }

    setState(() {
      relationshipFuture = loadPublicProfileRelationshipState(
        widget.profile.uid,
      );
    });
  }

  void showActionMessage(String message, {Color color = blue}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: CcsText(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> runAction(
    Future<void> Function() action, {
    required String successKey,
    required String errorKey,
    Color successColor = blue,
  }) async {
    if (busy) {
      return;
    }

    setState(() => busy = true);
    try {
      await action();
      showActionMessage(trText(successKey), color: successColor);
      refreshRelationship();
    } catch (error) {
      showActionMessage(
        localizedFriendActionError(error, errorKey),
        color: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> openMessage(PublicProfileRelationshipState relationship) async {
    if (widget.profile.currentViewerIsBlocked) {
      showActionMessage(
        trText('You cannot message this user.'),
        color: Colors.redAccent,
      );
      return;
    }

    await openMessageToUserFromContext(context, user);
  }

  Future<String?> requestReportReason() async {
    final reasonController = TextEditingController();
    String? errorText;
    var isSubmitting = false;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final cleanReason = reasonController.text.trim();
              if (cleanReason.isEmpty) {
                setDialogState(() => errorText = 'Reason is required.');
                return;
              }

              setDialogState(() {
                isSubmitting = true;
                errorText = null;
              });
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(const Duration(milliseconds: 120));

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.pop(dialogContext, cleanReason);
            }

            return AlertDialog(
              backgroundColor: panelGlass,
              title: CcsText(trText('Report user')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    '${trText('Tell moderators why you are reporting')} ${displayUsername(widget.profile.username)}.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    enabled: !isSubmitting,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 800,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: trText('Report reason'),
                      hintText: trText('Write the reason for reporting'),
                      prefixIcon: const Icon(Icons.report, color: blue),
                      errorText: errorText == null ? null : trText(errorText!),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: CcsText(trText('Cancel')),
                ),
                TextButton(
                  onPressed: isSubmitting ? null : () => unawaited(submit()),
                  child: CcsText(
                    trText(
                      isSubmitting ? 'Sending report...' : 'Submit report',
                    ),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    return reason;
  }

  Future<void> reportProfile() async {
    if (busy) {
      return;
    }

    final reason = await requestReportReason();
    if (reason == null) {
      return;
    }

    setState(() => busy = true);
    try {
      await submitUserReport(reportedUser: widget.profile, reason: reason);
      showActionMessage(trText('Report sent to moderators.'));
    } catch (error) {
      debugPrint('Could not send user report: $error');
      final message = error is FirebaseException
          ? '${trText('Could not send report.')} (${error.code})'
          : localizedFriendActionError(error, 'Could not send report.');
      showActionMessage(message, color: Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> acceptIncomingRequest() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return;
    }

    final doc = await safeFriendRequestGet(
      friendRequestIdFor(widget.profile.uid, firebaseUser.uid),
    );
    if (doc != null && doc.exists) {
      await acceptFriendRequest(FriendRequestData.fromFirestore(doc));
    }
  }

  Widget actionChipButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color color = blue,
    bool filled = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final cleanLabel = trText(label);

    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: CcsText(cleanLabel),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          shape: shape,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: CcsText(cleanLabel),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.7)),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        shape: shape,
      ),
    );
  }

  PopupMenuItem<String> popupActionItem({
    required IconData icon,
    required String label,
    required String value,
    Color color = Colors.white70,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, color: enabled ? color : Colors.white24, size: 18),
          const SizedBox(width: 10),
          CcsText(
            trText(label),
            style: TextStyle(
              color: enabled ? color : Colors.white38,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void handleMenuAction(
    String value,
    PublicProfileRelationshipState relationship,
  ) {
    switch (value) {
      case 'report':
        unawaited(reportProfile());
        break;
      case 'accept':
        unawaited(
          runAction(
            acceptIncomingRequest,
            successKey: 'Friend request accepted.',
            errorKey: 'Could not send request.',
          ),
        );
        break;
      case 'remove_friend':
        unawaited(
          runAction(
            () => removeFriendship(widget.profile.uid),
            successKey: 'Friend removed.',
            errorKey: 'Could not remove friend.',
            successColor: Colors.orangeAccent,
          ),
        );
        break;
      case 'add_friend':
        unawaited(
          runAction(
            () => sendFriendRequestToUser(user),
            successKey: 'Friend request sent.',
            errorKey: 'Could not send request.',
          ),
        );
        break;
      case 'block':
        unawaited(
          runAction(
            relationship.blockedByCurrentUser
                ? () => unblockUserById(widget.profile.uid)
                : () => blockUserById(user),
            successKey: relationship.blockedByCurrentUser
                ? 'User unblocked.'
                : 'User blocked.',
            errorKey: relationship.blockedByCurrentUser
                ? 'Could not unblock user.'
                : 'Could not block user.',
            successColor: relationship.blockedByCurrentUser
                ? blue
                : Colors.redAccent,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PublicProfileRelationshipState>(
      future: relationshipFuture,
      builder: (context, snapshot) {
        final relationship =
            snapshot.data ??
            PublicProfileRelationshipState(
              isSelf: widget.profile.uid == currentUser.uid,
            );

        if (relationship.isSelf) {
          return const SizedBox.shrink();
        }

        final isLoading =
            snapshot.connectionState == ConnectionState.waiting || busy;

        final items = <PopupMenuEntry<String>>[
          popupActionItem(
            icon: Icons.report_outlined,
            label: 'Report',
            value: 'report',
            color: Colors.orangeAccent,
            enabled: !isLoading,
          ),
          const PopupMenuDivider(height: 8),
        ];

        if (relationship.blockedByCurrentUser) {
          items.add(
            popupActionItem(
              icon: Icons.lock_open,
              label: 'Unblock user',
              value: 'block',
              color: blue,
              enabled: !isLoading,
            ),
          );
        } else if (relationship.incomingRequest) {
          items.add(
            popupActionItem(
              icon: Icons.person_add_alt_1,
              label: 'Accept',
              value: 'accept',
              color: blue,
              enabled: !isLoading,
            ),
          );
        } else if (relationship.isFriend) {
          items.add(
            popupActionItem(
              icon: Icons.person_remove_outlined,
              label: 'Remove friend',
              value: 'remove_friend',
              color: Colors.orangeAccent,
              enabled: !isLoading,
            ),
          );
        } else if (relationship.outgoingRequest) {
          items.add(
            popupActionItem(
              icon: Icons.mark_email_read_outlined,
              label: 'Sent',
              value: 'sent',
              enabled: false,
            ),
          );
        } else {
          items.add(
            popupActionItem(
              icon: Icons.person_add_alt_1,
              label: 'Add friend',
              value: 'add_friend',
              color: blue,
              enabled: !isLoading,
            ),
          );
        }

        if (!relationship.blockedByCurrentUser) {
          items.add(
            popupActionItem(
              icon: Icons.block,
              label: 'Block user',
              value: 'block',
              color: Colors.redAccent,
              enabled: !isLoading,
            ),
          );
        }

        return PopupMenuButton<String>(
          enabled: !isLoading,
          tooltip: trText('Action'),
          color: const Color(0xFF10131C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          onSelected: (value) => handleMenuAction(value, relationship),
          itemBuilder: (_) => items,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: blue,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(Icons.more_horiz, color: blue, size: 18),
                const SizedBox(width: 5),
                CcsText(
                  trText('Action'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> setProfileVerifiedStatus(
  BuildContext context,
  PublicUserProfileData profile,
  bool verified,
) async {
  if (!currentUserCanManageProfileCountry(profile.country)) {
    showAdminActionError(
      context,
      message: 'This user is outside your assigned countries',
      error: 'not-staff',
    );
    return;
  }

  if (profile.uid == currentUser.uid || profile.role != UserRole.user) {
    showAdminActionError(
      context,
      message: 'This account verification cannot be changed here',
      error: 'protected-user',
    );
    return;
  }

  try {
    await usersCollection().doc(profile.uid).debugSet({
      'verified': verified,
      'verifiedUpdatedByUid': currentUser.uid,
      'verifiedUpdatedBy': currentUser.username,
      'verifiedUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            verified
                ? 'User verification granted.'
                : 'User verification removed.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  } catch (error) {
    showAdminActionError(
      context,
      message: 'Could not update verified status',
      error: error,
    );
  }
}
