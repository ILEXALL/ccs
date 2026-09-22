import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart'
    show appPrimaryText, appSecondaryText, appSubtleText, blue;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class SpotOwnerSelector extends StatefulWidget {
  final SpotOwnerAssignment? selectedOwner;
  final ValueChanged<SpotOwnerAssignment?> onChanged;

  const SpotOwnerSelector({
    super.key,
    required this.selectedOwner,
    required this.onChanged,
  });

  @override
  State<SpotOwnerSelector> createState() => _SpotOwnerSelectorState();
}

class _SpotOwnerSelectorState extends State<SpotOwnerSelector>
    with LanguageReactiveState {
  final searchController = TextEditingController();
  String searchText = '';
  late bool isPicking;

  @override
  void initState() {
    super.initState();
    isPicking = widget.selectedOwner == null;
  }

  @override
  void didUpdateWidget(covariant SpotOwnerSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedOwner == null && oldWidget.selectedOwner != null) {
      isPicking = true;
    } else if (widget.selectedOwner != null &&
        oldWidget.selectedOwner?.uid != widget.selectedOwner?.uid) {
      isPicking = false;
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String userInitial(String username) {
    final cleanUsername = username.trim();
    return cleanUsername.isEmpty ? '?' : cleanUsername[0].toUpperCase();
  }

  bool userMatchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query) ||
        user.uid.toLowerCase().contains(query);
  }

  void selectOwner(FriendUserData user) {
    widget.onChanged(
      SpotOwnerAssignment(uid: user.uid, username: user.username),
    );
    searchController.clear();
    setState(() {
      searchText = '';
      isPicking = false;
    });
    FocusScope.of(context).unfocus();
  }

  Widget avatarForUser(FriendUserData user) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: CcsText(
                    userInitial(user.username),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : Center(
                child: CcsText(
                  userInitial(user.username),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }

  Widget ownerSearchField() {
    return TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onTap: () => setState(() => isPicking = true),
      onChanged: (value) => setState(() {
        searchText = value;
        isPicking = true;
      }),
      style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: trText('Spot owner'),
        hintText: widget.selectedOwner == null
            ? trText('Search nickname, name, or email')
            : trText('Search to change owner'),
        prefixIcon: const Icon(Icons.manage_accounts, color: blue),
        suffixIcon: searchText.trim().isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () {
                  searchController.clear();
                  setState(() => searchText = '');
                },
              )
            : null,
        labelStyle: TextStyle(color: appSecondaryText),
        hintStyle: TextStyle(color: appSubtleText),
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
    );
  }

  Widget selectedOwnerCard() {
    final owner = widget.selectedOwner;

    if (owner == null) {
      return const SizedBox.shrink();
    }

    final ownerLabel = owner.username.trim().isEmpty
        ? owner.uid
        : '@${owner.username}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CcsText(
                  'Selected owner',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                CcsText(
                  ownerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove owner',
            onPressed: () {
              widget.onChanged(null);
              setState(() => isPicking = true);
            },
            icon: const Icon(Icons.person_remove, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget ownerUserTile(FriendUserData user) {
    final isSelected = widget.selectedOwner?.uid == user.uid;

    return InkWell(
      onTap: () => selectOwner(user),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? blue.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? blue.withValues(alpha: 0.65) : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            avatarForUser(user),
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
                  CcsText(
                    user.email.trim().isEmpty ? user.name : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected ? Icons.check_circle : Icons.add_circle_outline,
              color: isSelected ? blue : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget ownerResults() {
    final query = searchText.trim();

    if (query.length < 2) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_search, color: Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: CcsText(
                trText('Enter at least 2 characters to search owners.'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersCollection()
          .orderBy('usernameKey')
          .limit(200)
          .debugSnapshots('spot form: owner search users listener'),
      builder: (context, snapshot) {
        final users =
            (snapshot.data?.docs
                        .map((doc) => FriendUserData.fromFirestore(doc))
                        .where((user) => user.canAppearInUserLists)
                        .where(userMatchesSearch)
                        .toList() ??
                    const <FriendUserData>[])
                .take(6)
                .toList();

        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                CcsText(
                  trText('Loading users...'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        if (users.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_search, color: Colors.white38),
                const SizedBox(width: 10),
                Expanded(
                  child: CcsText(
                    trText('No users found.'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < users.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              ownerUserTile(users[index]),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResults = searchText.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ownerSearchField(),
        if (widget.selectedOwner != null) ...[
          const SizedBox(height: 10),
          selectedOwnerCard(),
        ],
        if (showResults) ...[const SizedBox(height: 10), ownerResults()],
      ],
    );
  }
}
