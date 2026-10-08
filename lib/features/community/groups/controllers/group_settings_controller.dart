import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show chatsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/groups/data/group_api.dart'
    show privateGroupAction;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show confirmAndRemoveChat, currentUserOwnsGroupChat;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/friends/data/friends_repository.dart'
    show loadCurrentFriendUsers;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry;
import 'package:ccs_app/shared/media/entity_photos.dart'
    show uploadGroupAvatarPhoto;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/user_avatar.dart' show UserAvatarCircle;
import 'package:ccs_app/features/community/groups/controllers/group_settings_view_state.dart';

/// Coordinates actions and data loading for GroupSettingsScreen.
class GroupSettingsController implements GroupSettingsControllerActions {
  final GroupSettingsViewState host;
  GroupSettingsController(this.host);

  @override
  Future<void> pickGroupAvatar() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canEditGroupDetails || host.isSaving) {
      return;
    }

    final path = await pickPhotoFromPhone(
      viewContext,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (path == null || path.trim().isEmpty) {
      return;
    }

    host.updateView(() => host.isSaving = true);

    try {
      final uploadedUrl = await uploadGroupAvatarPhoto(
        groupId: host.widget.chat.id,
        localPhotoPath: path,
      );

      await chatsCollection().doc(host.widget.chat.id).debugSet({
        'photoUrl': uploadedUrl,
        'avatarUrl': uploadedUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.photoUrl = uploadedUrl);
      }
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not update group photo')}: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isSaving = false);
      }
    }
  }

  @override
  bool get isCurrentUserGroupOwner {
    return host.ownerUid == currentUser.uid;
  }

  @override
  bool get currentUserCanOverridePrivateGroup {
    if (currentUser.role == UserRole.moderator &&
        !currentUserCanModerateCountry(host.widget.chat.countryCode))
      return false;
    return isCurrentUserGroupOwner ||
        currentUserCanModerateCountry(
          host.widget.chat.countryCode,
          community: true,
        );
  }

  @override
  bool get canManageGroupMembers {
    if (currentUser.role == UserRole.moderator &&
        !currentUserCanModerateCountry(host.widget.chat.countryCode))
      return false;
    if (host.isPrivate) {
      return currentUserCanOverridePrivateGroup;
    }

    return currentUserCanOverridePrivateGroup ||
        host.moderatorIds.contains(currentUser.uid);
  }

  @override
  bool get canEditGroupDetails => canManageGroupMembers;

  @override
  ChatThreadData get localChatData => ChatThreadData(
    countryCode: host.widget.chat.countryCode,
    id: host.widget.chat.id,
    isGroup: host.widget.chat.isGroup,
    name: host.nameController.text.trim(),
    photoUrl: host.photoUrl,
    description: host.descriptionController.text.trim(),
    memberIds: host.memberIds,
    memberUsernames: host.memberUsernames,
    memberPhotoUrls: host.memberPhotoUrls,
    lastMessage: host.widget.chat.lastMessage,
    lastSenderUid: host.widget.chat.lastSenderUid,
    lastSenderUsername: host.widget.chat.lastSenderUsername,
    avatarUrl: host.widget.chat.avatarUrl,
    ownerUid: host.ownerUid,
    moderatorIds: host.moderatorIds,
    isPrivate: host.isPrivate,
    hiddenForUserIds: host.widget.chat.hiddenForUserIds,
    updatedAtMillis: host.widget.chat.updatedAtMillis,
  );

  @override
  Future<void> addMembersToGroup() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canManageGroupMembers || host.isSaving) return;

    final friends = await loadCurrentFriendUsers();
    if (!(host.mounted && viewContext.mounted)) return;

    final friendCandidates = friends
        .where((user) => !host.memberIds.contains(user.uid))
        .toList();
    final selected = <FriendUserData>[];
    final searchController = TextEditingController();

    var searchText = '';
    var searchResults = <FriendUserData>[];
    var isSearching = false;
    var searchGeneration = 0;
    var sheetActive = true;

    Future<void> runUserSearch(
      String rawQuery,
      void Function(void Function()) setSheetState,
    ) async {
      final query = rawQuery.trim().toLowerCase();
      final generation = ++searchGeneration;

      if (query.length < 2) {
        if (!sheetActive) return;
        setSheetState(() {
          searchResults = <FriendUserData>[];
          isSearching = false;
        });
        return;
      }

      if (!sheetActive) return;
      setSheetState(() => isSearching = true);

      try {
        // Search is intentionally performed only after the user types.
        // This keeps the default picker limited to friends instead of loading
        // a large list of unrelated app users.
        final snapshot = await usersCollection()
            .orderBy('usernameKey')
            .limit(200)
            .debugGet(null, 'group invite: searched users query');

        if (!sheetActive || generation != searchGeneration) return;

        final friendIds = friends.map((friend) => friend.uid).toSet();
        final results = snapshot.docs
            .map(FriendUserData.fromFirestore)
            .where((user) => user.uid != currentUser.uid)
            .where((user) => !host.memberIds.contains(user.uid))
            .where((user) => !friendIds.contains(user.uid))
            .where((user) => user.canAppearInUserLists)
            .where((user) {
              return user.username.toLowerCase().contains(query) ||
                  user.name.toLowerCase().contains(query) ||
                  user.email.toLowerCase().contains(query);
            })
            .take(20)
            .toList();

        results.sort(
          (a, b) =>
              a.username.toLowerCase().compareTo(b.username.toLowerCase()),
        );

        setSheetState(() {
          searchResults = results;
          isSearching = false;
        });
      } catch (error, stack) {
        debugPrint('Could not search users for group invite: $error');
        debugPrint('$stack');

        if (!sheetActive || generation != searchGeneration) return;
        setSheetState(() {
          searchResults = <FriendUserData>[];
          isSearching = false;
        });
      }
    }

    Widget userCheckboxTile(
      FriendUserData user,
      void Function(void Function()) setSheetState,
    ) {
      final checked = selected.any((item) => item.uid == user.uid);

      return CheckboxListTile(
        value: checked,
        onChanged: (value) {
          setSheetState(() {
            if (value == true) {
              if (!selected.any((item) => item.uid == user.uid)) {
                selected.add(user);
              }
            } else {
              selected.removeWhere((item) => item.uid == user.uid);
            }
          });
        },
        activeColor: blue,
        title: CcsText(
          displayUsername(user.username),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: user.name.trim().isEmpty
            ? null
            : CcsText(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              ),
        secondary: UserAvatarCircle(user: user, size: 34),
      );
    }

    await showModalBottomSheet<void>(
      context: viewContext,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final searchingOutsideFriends = searchText.trim().length >= 2;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CcsText(
                        'Add members',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        onChanged: (value) {
                          setSheetState(() => searchText = value);
                          runUserSearch(value, setSheetState);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search people outside your friends',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white54,
                          ),
                          suffixIcon: searchText.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    searchGeneration++;
                                    setSheetState(() {
                                      searchText = '';
                                      searchResults = <FriendUserData>[];
                                      isSearching = false;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white54,
                                  ),
                                ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: blue,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            searchingOutsideFriends
                                ? Icons.person_search
                                : Icons.people_outline,
                            color: blue,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          CcsText(
                            searchingOutsideFriends
                                ? 'Search results'
                                : 'Friends',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            if (searchingOutsideFriends) {
                              if (isSearching) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }

                              if (searchResults.isEmpty) {
                                return const Center(
                                  child: CcsText(
                                    'No users found.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                );
                              }

                              return ListView(
                                children: [
                                  for (final user in searchResults)
                                    userCheckboxTile(user, setSheetState),
                                ],
                              );
                            }

                            if (friendCandidates.isEmpty) {
                              return const Center(
                                child: CcsText(
                                  'No friends available to add.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              );
                            }

                            return ListView(
                              children: [
                                for (final friend in friendCandidates)
                                  userCheckboxTile(friend, setSheetState),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  Navigator.pop(context);
                                },
                          icon: const Icon(Icons.group_add),
                          label: CcsText('Add ${selected.length}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    sheetActive = false;
    searchGeneration++;

    // showModalBottomSheet completes when the route starts closing, not after
    // every descendant has finished deactivating. Give the TextField/IME and
    // inherited widgets time to detach before disposing the controller or
    // rebuilding the underlying group settings screen.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    searchController.dispose();

    if (!(host.mounted && viewContext.mounted) || selected.isEmpty) return;
    host.updateView(() => host.isSaving = true);
    try {
      final nextMemberIds = [...host.memberIds];
      final nextMemberUsernames = [...host.memberUsernames];
      final nextMemberPhotoUrls = [...host.memberPhotoUrls];

      for (final user in selected) {
        if (nextMemberIds.contains(user.uid)) {
          continue;
        }

        nextMemberIds.add(user.uid);
        nextMemberUsernames.add(user.username);
        nextMemberPhotoUrls.add(user.photoUrl ?? '');
      }

      await chatsCollection().doc(host.widget.chat.id).debugSet({
        'memberIds': nextMemberIds,
        'memberUsernames': nextMemberUsernames,
        'memberPhotoUrls': nextMemberPhotoUrls,
        // If a user was removed/left before and the chat was hidden for them,
        // adding them again must make the group visible in their chat list.
        'hiddenForUserIds': FieldValue.arrayRemove(
          selected.map((user) => user.uid).toList(),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() {
          host.memberIds = nextMemberIds;
          host.memberUsernames = nextMemberUsernames;
          host.memberPhotoUrls = nextMemberPhotoUrls;
        });

        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: CcsText(
              '${trText('Add members')}: ${selected.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('Could not add group members: $error');
      debugPrint('$stack');
    } finally {
      if ((host.mounted && viewContext.mounted))
        host.updateView(() => host.isSaving = false);
    }
  }

  @override
  Future<void> toggleGroupModerator(FriendUserData user) async {
    if (!isCurrentUserGroupOwner ||
        user.uid == currentUser.uid ||
        host.isSaving) {
      return;
    }

    final isModerator = host.moderatorIds.contains(user.uid);
    host.updateView(() => host.isSaving = true);
    try {
      final nextModeratorIds = [...host.moderatorIds];

      if (isModerator) {
        nextModeratorIds.remove(user.uid);
      } else if (!nextModeratorIds.contains(user.uid)) {
        nextModeratorIds.add(user.uid);
      }

      await chatsCollection().doc(host.widget.chat.id).debugSet({
        'moderatorIds': nextModeratorIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (host.mounted) {
        host.updateView(() => host.moderatorIds = nextModeratorIds);
      }
    } catch (error, stack) {
      debugPrint('Could not update group moderator: $error');
      debugPrint('$stack');
    } finally {
      if (host.mounted) host.updateView(() => host.isSaving = false);
    }
  }

  @override
  bool canRemoveGroupMember(FriendUserData user) {
    if (!canManageGroupMembers || host.isSaving) {
      return false;
    }

    if (user.uid == currentUser.uid || user.uid == host.ownerUid) {
      return false;
    }

    if (!isCurrentUserGroupOwner &&
        !userRoleIsStaff(currentUser.role) &&
        host.moderatorIds.contains(user.uid)) {
      return false;
    }

    return true;
  }

  @override
  Future<void> permanentlyDenyGroupMember(FriendUserData user) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final confirmed = await showDialog<bool>(
      context: viewContext,
      builder: (context) => AlertDialog(
        title: CcsText(
          communityText(
            en: 'Permanently deny group access?',
            ru: 'Запретить доступ к группе навсегда?',
            lv: 'Neatgriezeniski liegt piekļuvi grupai?',
          ),
        ),
        content: CcsText(displayUsername(user.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: CcsText(trText('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: CcsText(trText('Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !(host.mounted && viewContext.mounted)) return;
    try {
      await privateGroupAction({
        'action': 'ban',
        'chatId': host.widget.chat.id,
        'requesterUid': user.uid,
      });
      if ((host.mounted && viewContext.mounted)) Navigator.pop(viewContext);
    } catch (_) {
      if ((host.mounted && viewContext.mounted))
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            content: CcsText(trText('Could not update group. Please retry.')),
          ),
        );
    }
  }

  @override
  Future<void> removeGroupMember(FriendUserData user) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canRemoveGroupMember(user)) {
      return;
    }

    final shouldRemove = await showDialog<bool>(
      context: viewContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(
            trText('Remove member?'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: CcsText(
            '${displayUsername(user.username)} ${trText('will be removed from this group.')}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: CcsText(trText('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: CcsText(
                trText('Remove'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) {
      return;
    }

    host.updateView(() => host.isSaving = true);
    try {
      final nextMemberIds = [...host.memberIds];
      final nextMemberUsernames = [...host.memberUsernames];
      final nextMemberPhotoUrls = [...host.memberPhotoUrls];
      final nextModeratorIds = [...host.moderatorIds];

      final index = nextMemberIds.indexOf(user.uid);
      if (index >= 0) {
        nextMemberIds.removeAt(index);
        if (index < nextMemberUsernames.length) {
          nextMemberUsernames.removeAt(index);
        }
        if (index < nextMemberPhotoUrls.length) {
          nextMemberPhotoUrls.removeAt(index);
        }
      }
      nextModeratorIds.remove(user.uid);

      await chatsCollection().doc(host.widget.chat.id).debugSet({
        'memberIds': nextMemberIds,
        'memberUsernames': nextMemberUsernames,
        'memberPhotoUrls': nextMemberPhotoUrls,
        'moderatorIds': nextModeratorIds,
        // Keep the group hidden for the removed user even if their local cache
        // still has an older chat snapshot for a moment.
        'hiddenForUserIds': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() {
          host.memberIds = nextMemberIds;
          host.memberUsernames = nextMemberUsernames;
          host.memberPhotoUrls = nextMemberPhotoUrls;
          host.moderatorIds = nextModeratorIds;
        });
      }
    } catch (error, stack) {
      debugPrint('Could not remove group member: $error');
      debugPrint('$stack');
    } finally {
      if ((host.mounted && viewContext.mounted))
        host.updateView(() => host.isSaving = false);
    }
  }

  @override
  Future<void> saveGroup() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canEditGroupDetails) {
      return;
    }

    final name = host.nameController.text.trim();
    final description = host.descriptionController.text.trim();

    host.updateView(() => host.isSaving = true);

    try {
      await chatsCollection().doc(host.widget.chat.id).debugSet({
        'name': name.isEmpty ? host.widget.chat.name : name,
        'description': description,
        'isPrivate': host.isPrivate,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if ((host.mounted && viewContext.mounted)) {
        Navigator.pop(viewContext);
      }
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not update group')}: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isSaving = false);
      }
    }
  }

  @override
  Future<void> removeGroupOrLeave() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isSaving) {
      return;
    }

    final removed = await confirmAndRemoveChat(viewContext, localChatData);
    if (removed && (host.mounted && viewContext.mounted)) {
      Navigator.pop(viewContext, true);
    }
  }

  @override
  Future<void> deleteGroupExplicitly() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isSaving || !currentUserOwnsGroupChat(localChatData)) {
      return;
    }

    final removed = await confirmAndRemoveChat(
      viewContext,
      localChatData,
      forceDeleteGroup: true,
    );
    if (removed && (host.mounted && viewContext.mounted)) {
      Navigator.pop(viewContext, true);
    }
  }
}
