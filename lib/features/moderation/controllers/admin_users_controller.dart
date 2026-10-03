import 'package:ccs_app/features/moderation/models/admin_user_sort.dart';
import 'package:ccs_app/features/moderation/screens/admin_xp_grant_screen.dart';
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show deviceBansCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart'
    show displayUsername, usernameKey;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanManageProfileCountry;
import 'package:ccs_app/features/moderation/models/admin_user.dart'
    show AdminBanInput, AdminUserData;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show showAdminActionError;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/shared/models/countries.dart'
    show
        allSupportedCountryNames,
        countryFlagEmoji,
        countryIsoCode,
        localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/features/moderation/controllers/admin_users_view_state.dart';

/// Coordinates actions and data loading for AdminUsersScreen.
class AdminUsersController implements AdminUsersControllerActions {
  final AdminUsersViewState host;
  AdminUsersController(this.host);

  @override
  void resetUserPages() {
    host.pageIndex = 0;
    host.pageStartDocuments
      ..clear()
      ..add(null);
  }

  @override
  void setBannedOnly(bool value) {
    if (host.bannedOnly == value) {
      return;
    }

    host.updateView(() {
      host.bannedOnly = value;
      resetUserPages();
      if (host.searchText.isNotEmpty) {
        host.searchFuture = searchAdminUsers(host.searchText);
      }
    });
  }

  @override
  void setSortMode(AdminUserSortMode value) {
    if (host.sortMode == value) {
      return;
    }

    host.updateView(() {
      host.sortMode = value;
      resetUserPages();
      if (host.searchText.isNotEmpty) {
        host.searchFuture = searchAdminUsers(host.searchText);
      }
    });
  }

  @override
  int compareAdminUsers(AdminUserData first, AdminUserData second) {
    if (host.sortMode == AdminUserSortMode.recent) {
      if (first.appearsOnline != second.appearsOnline) {
        return first.appearsOnline ? -1 : 1;
      }

      final lastSeenCompare = second.lastSeenAtMillis.compareTo(
        first.lastSeenAtMillis,
      );
      if (lastSeenCompare != 0) {
        return lastSeenCompare;
      }
    }

    return first.username.toLowerCase().compareTo(
      second.username.toLowerCase(),
    );
  }

  @override
  Query<Map<String, dynamic>> usersPageQuery() {
    Query<Map<String, dynamic>> query = usersCollection();
    if (host.bannedOnly) {
      query = query.where('banned', isEqualTo: true);
    }
    query = host.sortMode == AdminUserSortMode.recent
        ? query.orderBy('lastSeenAt', descending: true)
        : query.orderBy('usernameKey');

    final startDocument = host.pageStartDocuments[host.pageIndex];
    if (startDocument != null) {
      query = query.startAfterDocument(startDocument);
    }

    // One extra document tells us whether a next page exists.
    return query.limit(host.configUsersPerPage + 1);
  }

  @override
  void queueAdminUserSearch(String value) {
    final nextSearchText = usernameKey(value);
    host.searchDebounce?.cancel();

    host.updateView(() {
      host.searchText = nextSearchText;
      host.searchFuture = null;
    });

    if (nextSearchText.isEmpty) {
      return;
    }

    host.searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!host.mounted || host.searchText != nextSearchText) {
        return;
      }

      host.updateView(() {
        host.searchFuture = searchAdminUsers(nextSearchText);
      });
    });
  }

  @override
  Future<List<AdminUserData>> searchAdminUsers(String queryText) async {
    Query<Map<String, dynamic>> query = usersCollection();
    if (host.bannedOnly) {
      query = query.where('banned', isEqualTo: true);
    }

    final snapshot = await query
        .orderBy('usernameKey')
        .startAt([queryText])
        .endAt(['$queryText\uf8ff'])
        .limit(12)
        .debugGet(null, 'admin: user prefix search');
    final users = snapshot.docs
        .map(AdminUserData.fromFirestore)
        .where((user) => !user.deleted)
        .toList();
    users.sort(compareAdminUsers);
    return users;
  }

  @override
  Future<bool> canManageUser(BuildContext context, AdminUserData user) async {
    if (!currentUserCanManageProfileCountry(user.country)) {
      showAdminActionError(
        context,
        message: 'This user is outside your assigned countries',
        error: 'regional-moderator-scope',
      );
      return false;
    }
    if (user.uid == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'You cannot manage your own account here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    if (user.role == UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Admin accounts cannot be managed here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    if (currentUser.role == UserRole.moderator &&
        user.role == UserRole.moderator) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Moderators cannot manage other moderators.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    return true;
  }

  @override
  bool canShowManagementActions(AdminUserData user) {
    if (!currentUserCanManageProfileCountry(user.country)) return false;
    if (user.uid == currentUser.uid || user.role == UserRole.admin) {
      return false;
    }

    return currentUser.role != UserRole.moderator ||
        user.role != UserRole.moderator;
  }

  @override
  Future<Set<String>?> requestModeratorCountryCodes(
    BuildContext context,
    AdminUserData user,
  ) async {
    final searchController = TextEditingController();
    final selectedCodes = <String>{...user.moderatorCountryCodes};
    String searchQuery = '';
    String? errorText;

    try {
      return await showDialog<Set<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchQuery.trim().toLowerCase();
            final countries = allSupportedCountryNames()
                .where(
                  (country) =>
                      query.isEmpty ||
                      localizedCountryName(
                        country,
                      ).toLowerCase().contains(query) ||
                      country.toLowerCase().contains(query),
                )
                .toList(growable: false);

            void toggleCountry(String code) {
              setDialogState(() {
                errorText = null;
                if (!selectedCodes.remove(code)) {
                  if (selectedCodes.length >= 30) {
                    errorText = trText(
                      'A moderator can be assigned to up to 30 countries.',
                    );
                    return;
                  }
                  selectedCodes.add(code);
                }
              });
            }

            return AlertDialog(
              backgroundColor: panelGlass,
              title: CcsText(trText('Assign moderator countries')),
              content: SizedBox(
                width: 620,
                height: math.min(540, MediaQuery.sizeOf(context).height * 0.7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      trText(
                        'This moderator can review spots only in the selected countries.',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      onChanged: (value) =>
                          setDialogState(() => searchQuery = value),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: trText('Search countries'),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CcsText(
                      '${selectedCodes.length} ${trText('assigned countries')}',
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 6),
                      CcsText(
                        errorText!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        itemCount: countries.length,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisExtent: 52,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemBuilder: (context, index) {
                          final country = countries[index];
                          final code = countryIsoCode(country)!;
                          final selected = selectedCodes.contains(code);
                          return Material(
                            color: selected
                                ? blue.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => toggleCountry(code),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected ? blue : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: selected,
                                      activeColor: blue,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (_) => toggleCountry(code),
                                    ),
                                    CcsText(
                                      countryFlagEmoji(code),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: CcsText(
                                        localizedCountryName(code),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: CcsText(trText('Cancel')),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (selectedCodes.isEmpty) {
                      setDialogState(
                        () => errorText = trText(
                          'Select at least one country for the moderator.',
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, <String>{...selectedCodes});
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: CcsText(trText('Save assignment')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  @override
  Future<void> setModeratorStatus(
    BuildContext context,
    AdminUserData user,
    bool makeModerator,
  ) async {
    if (currentUser.role != UserRole.admin) {
      showAdminActionError(
        context,
        message: 'Only admins can change roles',
        error: 'not-admin',
      );
      return;
    }

    if (user.uid == currentUser.uid || user.role == UserRole.admin) {
      showAdminActionError(
        context,
        message: 'This role cannot be changed here',
        error: 'protected-user',
      );
      return;
    }

    Set<String> assignedCountryCodes = const <String>{};
    if (makeModerator) {
      final selection = await requestModeratorCountryCodes(context, user);
      if (selection == null || !context.mounted) {
        return;
      }
      assignedCountryCodes = selection;
    }

    try {
      await usersCollection().doc(user.uid).debugSet({
        'role': makeModerator ? 'moderator' : 'user',
        'moderatorCountryCodes': assignedCountryCodes.toList(growable: false)
          ..sort(),
        'roleUpdatedByUid': currentUser.uid,
        'roleUpdatedBy': currentUser.username,
        'roleUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: blue,
            content: CcsText(
              makeModerator
                  ? trText('Moderator assigned.')
                  : trText('Moderator removed.'),
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
        message: trText('Could not update role'),
        error: error,
      );
    }
  }

  @override
  Future<void> setCommunityModeratorStatus(
    BuildContext context,
    AdminUserData user,
    bool makeModerator,
  ) async {
    if (currentUser.role != UserRole.admin) {
      showAdminActionError(
        context,
        message: trText('Only admins can change community moderation access'),
        error: 'not-admin',
      );
      return;
    }

    if (user.uid == currentUser.uid || user.role == UserRole.admin) {
      showAdminActionError(
        context,
        message: trText('This access cannot be changed here'),
        error: 'protected-user',
      );
      return;
    }

    Set<String>? assignedCountries;
    if (makeModerator) {
      assignedCountries = await requestModeratorCountryCodes(context, user);
      if (assignedCountries == null || assignedCountries.isEmpty) return;
    }

    try {
      await usersCollection().doc(user.uid).debugSet({
        if (assignedCountries != null)
          'moderatorCountryCodes': assignedCountries.toList()..sort(),
        'globalChatModerator': makeModerator,
        'globalModerator': makeModerator,
        'globalModeratorUpdatedByUid': currentUser.uid,
        'globalModeratorUpdatedBy': currentUser.username,
        'globalModeratorUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: blue,
            content: CcsText(
              makeModerator
                  ? trText('Community moderator assigned.')
                  : trText('Community moderator removed.'),
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
        message: trText('Could not update community moderation access'),
        error: error,
      );
    }
  }

  @override
  Future<AdminBanInput?> requestBanInput(
    BuildContext context,
    AdminUserData user,
  ) async {
    final daysController = TextEditingController(text: '7');
    final reasonController = TextEditingController(text: user.banReason);
    String? errorText;
    var isClosing = false;

    final input = await showDialog<AdminBanInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (isClosing) {
                return;
              }

              final days = int.tryParse(daysController.text.trim());
              final reason = reasonController.text.trim();

              if (days == null || days < 1 || days > 3650) {
                setDialogState(
                  () => errorText = 'Enter a valid number of days.',
                );
                return;
              }

              if (reason.isEmpty) {
                setDialogState(() => errorText = 'Reason is required.');
                return;
              }

              FocusManager.instance.primaryFocus?.unfocus();
              setDialogState(() => isClosing = true);
              await Future<void>.delayed(const Duration(milliseconds: 180));

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.pop(
                dialogContext,
                AdminBanInput(days: days, reason: reason),
              );
            }

            return AlertDialog(
              backgroundColor: panelGlass,
              title: CcsText(trText('Ban user')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: daysController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: trText('Ban duration (days)'),
                      prefixIcon: const Icon(Icons.event_busy, color: blue),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: trText('Ban reason'),
                      prefixIcon: const Icon(Icons.report, color: blue),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CcsText(
                        trText(errorText!),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isClosing
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: CcsText(trText('Cancel')),
                ),
                TextButton(
                  onPressed: isClosing ? null : () => unawaited(submit()),
                  child: CcsText(
                    trText(isClosing ? 'Banning user...' : 'Confirm ban'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    daysController.dispose();
    reasonController.dispose();
    return input;
  }

  @override
  Future<void> banUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) return;
    final input = await requestBanInput(context, user);
    if (input == null) return;
    final requestId = usersCollection().doc().id;
    try {
      await sendModerationAction({
        'action': 'ban_user',
        'targetUserId': user.uid,
        'days': input.days,
        'reason': input.reason,
        'requestId': requestId,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: CcsText(trText('User banned.'))));
      }
    } catch (error) {
      if (context.mounted) {
        showAdminActionError(
          context,
          message: trText('Could not ban user'),
          error: error,
        );
      }
    }
  }

  @override
  Future<void> unbanUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).debugSet({
        'banned': false,
        'bannedUntil': FieldValue.delete(),
        'banReason': FieldValue.delete(),
        'knownDeviceIdsAtBan': FieldValue.delete(),
        'unbannedByUid': currentUser.uid,
        'unbannedBy': currentUser.username,
        'unbannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (final deviceId in user.deviceIds) {
        final cleanDeviceId = deviceId.trim();
        if (cleanDeviceId.isEmpty) {
          continue;
        }
        await deviceBansCollection().doc(cleanDeviceId).debugSet({
          'banned': false,
          'unbannedByUid': currentUser.uid,
          'unbannedBy': currentUser.username,
          'unbannedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: CcsText(
              'User unbanned.',
              style: TextStyle(
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
        message: 'Could not unban user',
        error: error,
      );
    }
  }

  @override
  Future<void> deleteUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(trText('Delete user?')),
          content: CcsText(
            'This will remove ${displayUsername(user.username)} from the users list.',
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

    if (confirmed != true) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).debugSet({
        'deleted': true,
        'banned': true,
        'bannedUntil': null,
        'publicProfile': false,
        'photoUrl': '',
        'avatarPath': null,
        'bio': 'Profile removed.',
        'garage': <Object>[],
        'settings': const UserSettingsData(
          instagram: '',
          tiktok: '',
          telegram: '',
          reviewNotifications: false,
          likeNotifications: false,
          commentNotifications: false,
          newSpotNotifications: false,
          newMessageNotifications: false,
          xpNotifications: false,
          friendAtSpotNotifications: false,
          friendLiveShareNotifications: false,
          publicProfile: false,
          showGarage: false,
        ).toFirebase(),
        'deletedByUid': currentUser.uid,
        'deletedBy': currentUser.username,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'User deleted.',
              style: TextStyle(
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
        message: 'Could not delete user',
        error: error,
      );
    }
  }

  @override
  void handleUserAction(
    BuildContext context,
    AdminUserData user,
    String action,
  ) {
    switch (action) {
      case 'award_xp':
        if (currentUser.role != UserRole.admin ||
            !canShowManagementActions(user) ||
            user.banned ||
            user.deleted) {
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminXpGrantScreen(
              request: xpScreenRequest,
              selectedUsername: user.username,
              selectedUserId: user.uid,
            ),
          ),
        );
        break;
      case 'open':
        openUserProfile(
          context,
          uid: user.uid,
          fallbackUsername: user.username,
        );
        break;
      case 'ban':
        banUser(context, user);
        break;
      case 'unban':
        unbanUser(context, user);
        break;
      case 'make_moderator':
        unawaited(setModeratorStatus(context, user, true));
        break;
      case 'edit_moderator_countries':
        unawaited(setModeratorStatus(context, user, true));
        break;
      case 'remove_moderator':
        unawaited(setModeratorStatus(context, user, false));
        break;
      case 'make_community_moderator':
        setCommunityModeratorStatus(context, user, true);
        break;
      case 'remove_community_moderator':
        setCommunityModeratorStatus(context, user, false);
        break;
      case 'delete':
        deleteUser(context, user);
        break;
    }
  }
}
