import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show friendRequestsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show FriendUserSearch;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show
        acceptFriendRequest,
        areUsersFriends,
        cancelFriendRequest,
        declineFriendRequest,
        friendRequestIdFor,
        incomingFriendRequestCountStream,
        localizedFriendActionError,
        pendingRequestStatusBetweenUsers,
        removeFriendship,
        sendFriendRequestToUser;
import 'package:ccs_app/features/friends/models/friend_request.dart'
    show FriendRequestData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show watchCurrentFriendUsers;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class FriendsScreen extends StatefulWidget {
  final int initialTabIndex;

  const FriendsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with LanguageReactiveState {
  final searchController = TextEditingController();
  late final FriendUserSearch userSearch;
  String get searchText => userSearch.query;

  @override
  void initState() {
    super.initState();
    userSearch = FriendUserSearch(
      currentUid: FirebaseAuth.instance.currentUser?.uid ?? '',
      loadUsers: () => usersCollection()
          .debugSnapshots('friends: searchable user directory')
          .map(
            (snapshot) =>
                snapshot.docs.map(FriendUserData.fromFirestore).toList(),
          ),
    );
    userSearch.addListener(searchChanged);
  }

  void searchChanged() {
    if (mounted) setState(() {});
  }

  void queueUsersSearch(String value) => userSearch.search(value);

  @override
  void dispose() {
    userSearch.removeListener(searchChanged);
    userSearch.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<FriendUserData?> loadFriendUser(String uid) async {
    final snapshot = await usersCollection().doc(uid).debugGet();

    if (!snapshot.exists) {
      return null;
    }

    return FriendUserData.fromFirestore(snapshot);
  }

  void showFriendActionMessage(String message, {Color color = blue}) {
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

  Future<void> sendRequest(FriendUserData user) async {
    try {
      await sendFriendRequestToUser(user);
      showFriendActionMessage(trText('Friend request sent.'));
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        localizedFriendActionError(error, 'Could not send request.'),
        color: Colors.redAccent,
      );
    }
  }

  Future<void> acceptRequest(FriendRequestData request) async {
    try {
      await acceptFriendRequest(request);
      showFriendActionMessage('${request.fromUsername} added to friends.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not accept request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> declineRequest(FriendRequestData request) async {
    try {
      await declineFriendRequest(request);
      showFriendActionMessage('Friend request declined.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not decline request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> cancelRequest(FriendRequestData request) async {
    try {
      await cancelFriendRequest(request);
      showFriendActionMessage('Friend request cancelled.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not cancel request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> removeFriend(FriendUserData user) async {
    try {
      await removeFriendship(user.uid);
      showFriendActionMessage(
        '${user.username} removed from friends.',
        color: Colors.redAccent,
      );
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        localizedFriendActionError(error, 'Could not remove friend.'),
        color: Colors.redAccent,
      );
    }
  }

  Widget userAvatar({
    required String username,
    String? photoUrl,
    String? avatarPath,
    bool verified = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: blue.withValues(alpha: 0.45)),
          ),
          child: ClipOval(
            child: localFileExists(avatarPath)
                ? Image.file(File(avatarPath!), fit: BoxFit.cover)
                : (photoUrl != null && photoUrl.trim().isNotEmpty)
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: CcsText(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: CcsText(
                      username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
        ),
        if (verified)
          const Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.verified, color: blue, size: 17),
          ),
      ],
    );
  }

  Widget friendUserTile({
    required FriendUserData user,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            userAvatar(
              username: user.username,
              photoUrl: user.photoUrl,
              avatarPath: user.avatarPath,
              verified: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: CcsText(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      UserPrimaryBadge(
                        role: user.role,
                        verified: user.verified,
                        globalChatModerator: user.globalChatModerator,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      CcsText(
                        user.appearsOnline ? 'online' : 'offline',
                        style: TextStyle(
                          color: user.appearsOnline
                              ? Colors.greenAccent
                              : Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CcsText(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget actionButton({
    required String label,
    required VoidCallback? onPressed,
    Color color = blue,
    bool outlined = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: shape,
        ),
        child: CcsText(trText(label)),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: shape,
      ),
      child: CcsText(trText(label)),
    );
  }

  Widget friendsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.group,
        title: 'Log in required',
        text: 'Log in before using friends.',
      );
    }

    return StreamBuilder<List<FriendUserData>>(
      stream: watchCurrentFriendUsers(),
      builder: (context, snapshot) {
        final friends = snapshot.data ?? const <FriendUserData>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: blue),
            ),
          );
        }

        if (friends.isEmpty) {
          return const EmptyStateCard(
            icon: Icons.group_outlined,
            title: 'No friends yet',
            text: 'Use Find Users to send your first friend request.',
          );
        }

        return Column(
          children: [
            for (final user in friends)
              friendUserTile(
                user: user,
                subtitle: user.name,
                onTap: () => openUserProfile(
                  context,
                  uid: user.uid,
                  fallbackUsername: user.username,
                ),
                trailing: actionButton(
                  label: 'Remove',
                  color: Colors.redAccent,
                  outlined: true,
                  onPressed: () => removeFriend(user),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget friendRequestTile({
    required String uid,
    required String username,
    required String name,
    required Widget trailing,
  }) {
    return InkWell(
      onTap: () =>
          openUserProfile(context, uid: uid, fallbackUsername: username),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            userAvatar(username: username),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  CcsText(
                    name,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget requestsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.mark_email_unread_outlined,
        title: 'Log in required',
        text: 'Log in before using friend requests.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CcsText(
          'Incoming requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('toUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .debugSnapshots('friends: incoming requests tab listener'),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.inbox_outlined,
                title: 'No incoming requests',
                text: 'Friend invites sent to you will appear here.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  friendRequestTile(
                    uid: request.fromUid,
                    username: request.fromUsername,
                    name: request.fromName,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        actionButton(
                          label: 'Accept',
                          onPressed: () => acceptRequest(request),
                        ),
                        const SizedBox(width: 6),
                        actionButton(
                          label: 'Decline',
                          color: Colors.redAccent,
                          outlined: true,
                          onPressed: () => declineRequest(request),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const CcsText(
          'Sent requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('fromUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .debugSnapshots('friends: sent requests tab listener'),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.outbox_outlined,
                title: 'No sent requests',
                text: 'Requests you send will appear here until accepted.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  friendRequestTile(
                    uid: request.toUid,
                    username: request.toUsername,
                    name: request.toName,
                    trailing: actionButton(
                      label: 'Cancel',
                      color: Colors.redAccent,
                      outlined: true,
                      onPressed: () => cancelRequest(request),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget findUsersTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.person_search,
        title: 'Log in required',
        text: 'Log in before finding friends.',
      );
    }

    return Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: queueUsersSearch,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: trText('Search users'),
            hintText: trText('nickname or name'),
            prefixIcon: const Icon(Icons.search, color: blue),
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: blue, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (searchText.runes.length < 2)
          const EmptyStateCard(
            icon: Icons.person_search,
            title: 'Search users',
            text: 'Type at least 2 characters to search.',
          )
        else
          Builder(
            builder: (context) {
              if (userSearch.loading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: blue),
                  ),
                );
              }

              if (userSearch.error != null) {
                return TextButton.icon(
                  onPressed: userSearch.retry,
                  icon: const Icon(Icons.refresh),
                  label: CcsText(trText('Could not load users. Tap to retry.')),
                );
              }

              final users = userSearch.results;

              if (users.isEmpty) {
                return const EmptyStateCard(
                  icon: Icons.person_search,
                  title: 'No users found',
                  text: 'Try searching by nickname or name.',
                );
              }

              return Column(
                children: [
                  for (final user in users)
                    FutureBuilder<String>(
                      future: friendStatusLabelForUser(
                        firebaseUser.uid,
                        user.uid,
                      ),
                      builder: (context, statusSnapshot) {
                        final status = statusSnapshot.data ?? 'loading';
                        final isFriend = status == 'friends';
                        final incoming = status == 'incoming';
                        final outgoing = status == 'outgoing';

                        return friendUserTile(
                          user: user,
                          subtitle: user.name,
                          onTap: () => openUserProfile(
                            context,
                            uid: user.uid,
                            fallbackUsername: user.username,
                          ),
                          trailing: incoming
                              ? actionButton(
                                  label: 'Accept',
                                  onPressed: () async {
                                    final doc = await friendRequestsCollection()
                                        .doc(
                                          friendRequestIdFor(
                                            user.uid,
                                            firebaseUser.uid,
                                          ),
                                        )
                                        .debugGet();
                                    if (doc.exists) {
                                      await acceptRequest(
                                        FriendRequestData.fromFirestore(doc),
                                      );
                                    }
                                  },
                                )
                              : actionButton(
                                  label: isFriend
                                      ? 'Friends'
                                      : outgoing
                                      ? 'Sent'
                                      : status == 'loading'
                                      ? '...'
                                      : 'Add',
                                  outlined: isFriend || outgoing,
                                  onPressed:
                                      (isFriend ||
                                          outgoing ||
                                          status == 'loading')
                                      ? null
                                      : () => sendRequest(user),
                                ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Future<String> friendStatusLabelForUser(
    String currentUid,
    String otherUid,
  ) async {
    if (await areUsersFriends(currentUid, otherUid)) {
      return 'friends';
    }

    return await pendingRequestStatusBetweenUsers(currentUid, otherUid) ??
        'none';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const CcsText('Friends'),
          backgroundColor: Colors.transparent,
          foregroundColor: blue,
          bottom: TabBar(
            indicatorColor: blue,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: const Icon(Icons.group), text: trText('Friends')),
              Tab(
                icon: const _IncomingFriendRequestTabIcon(),
                text: trText('Requests'),
              ),
              Tab(icon: const Icon(Icons.person_search), text: trText('Find')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
              child: friendsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
              child: requestsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
              child: findUsersTab(),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingFriendRequestTabIcon extends StatelessWidget {
  const _IncomingFriendRequestTabIcon();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: incomingFriendRequestCountStream(),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: CcsText(count > 9 ? '9+' : '$count'),
          child: const Icon(Icons.mark_email_unread_outlined),
        );
      },
    );
  }
}
