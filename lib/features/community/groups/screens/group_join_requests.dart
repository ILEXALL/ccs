import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/groups/data/group_api.dart'
    show privateGroupAction;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show UserAvatarCircle, UserAvatarFallback, friendUserFromSnapshot;

class GroupJoinRequestsScreen extends StatefulWidget {
  final String chatId;
  final Future<Map<String, dynamic>> Function(Map<String, Object?>)?
  requestAction;
  final Future<FriendUserData?> Function(String)? applicantLoader;
  const GroupJoinRequestsScreen({
    super.key,
    required this.chatId,
    this.requestAction,
    this.applicantLoader,
  });
  @override
  State<GroupJoinRequestsScreen> createState() =>
      _GroupJoinRequestsScreenState();
}

class _GroupJoinRequestsScreenState extends State<GroupJoinRequestsScreen>
    with LanguageReactiveState {
  late Future<Map<String, dynamic>> requests;
  final Map<String, Future<FriendUserData?>> profiles = {};
  String? busyUid;
  bool get busy => busyUid != null;

  Future<Map<String, dynamic>> action(Map<String, Object?> body) =>
      (widget.requestAction ?? privateGroupAction)(body);

  @override
  void initState() {
    super.initState();
    requests = load();
  }

  Future<Map<String, dynamic>> load() =>
      action({'action': 'requests', 'chatId': widget.chatId});

  void refresh() {
    final nextRequests = load();
    setState(() {
      requests = nextRequests;
    });
  }

  Future<FriendUserData?> loadProfile(String uid) => profiles.putIfAbsent(
    uid,
    () => widget.applicantLoader != null
        ? widget.applicantLoader!(uid)
        : usersCollection().doc(uid).get().then(friendUserFromSnapshot),
  );

  Future<void> decide(String uid, String decision) async {
    if (busy) return;
    setState(() {
      busyUid = uid;
    });
    try {
      await action({
        'action': 'decide',
        'chatId': widget.chatId,
        'requesterUid': uid,
        'decision': decision,
      });
      if (!mounted) return;
      refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CcsText(
              trText('Could not submit decision. Please retry.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busyUid = null;
        });
      }
    }
  }

  Widget requestCard(Map<String, dynamic> item) {
    final uid = item['uid'] as String;
    return FutureBuilder<FriendUserData?>(
      future: loadProfile(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final username =
            user?.username ?? stringFromFirebase(item['username'], 'driver');
        final name = user?.name.trim() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  user == null
                      ? const UserAvatarFallback(
                          size: 62,
                          icon: Icons.person_outline_rounded,
                        )
                      : UserAvatarCircle(user: user, size: 62),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CcsText(
                          name.isEmpty ? displayUsername(username) : name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (name.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          CcsText(
                            displayUsername(username),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (user?.verified == true) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: blue,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              CcsText(
                                trText('Verified'),
                                style: const TextStyle(
                                  color: blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CcsText(
                trText('Wants to join your group'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              TextButton.icon(
                onPressed: () => openUserProfile(
                  context,
                  uid: uid,
                  fallbackUsername: username,
                ),
                icon: const Icon(Icons.account_circle_outlined, size: 17),
                label: CcsText(trText('View profile')),
                style: TextButton.styleFrom(
                  foregroundColor: blue,
                  padding: EdgeInsets.zero,
                ),
              ),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CcsText(
                    trText(
                      'Profile preview unavailable. Open the profile to retry.',
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              Divider(height: 20, color: Colors.white.withValues(alpha: 0.08)),
              if (busyUid == uid) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => decide(uid, 'accepted'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF218654),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: CcsText(trText('Accept')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => decide(uid, 'rejected'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFBA3945),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: CcsText(trText('Reject')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: panel,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: CcsText(trText('Join requests')),
      actions: [
        IconButton(
          onPressed: busy ? null : refresh,
          tooltip: trText('Refresh'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: requests,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
              label: CcsText(trText('Could not load requests. Tap to retry.')),
            ),
          );
        }
        final items = (snapshot.data?['requests'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      color: blue,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  CcsText(
                    trText('No pending requests.'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: CcsText(
                trText(
                  'Review each profile before granting access to your group.',
                ),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            for (final item in items) requestCard(item),
          ],
        );
      },
    ),
  );
}
