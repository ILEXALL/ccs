import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show chatsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserHomeCountryCode, currentUserProfileRevision;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/community/groups/data/group_api.dart'
    show privateGroupAction;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show ChatThreadTile;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/community/groups/data/group_directory_cache.dart'
    show GroupDirectoryCache;
import 'package:ccs_app/features/community/groups/data/group_repository.dart'
    show groupMemberCountLabel, groupVisibilityLabel;
import 'package:ccs_app/features/community/groups/screens/group_join_requests.dart'
    show GroupJoinRequestsScreen;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show availableCommunityCountryCodes;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/countries.dart' show localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show UserAvatarFallback;

class PrivateGroupDirectory extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(Map<String, Object?>)?
  requestAction;
  final String membershipRevision;
  final List<ChatThreadData> chats;
  final String currentUid;
  final Map<String, int> unreadCountsByChatId;
  const PrivateGroupDirectory({
    super.key,
    this.requestAction,
    required this.membershipRevision,
    required this.chats,
    required this.currentUid,
    required this.unreadCountsByChatId,
  });
  @override
  State<PrivateGroupDirectory> createState() => _PrivateGroupDirectoryState();
}

class _PrivateGroupDirectoryState extends State<PrivateGroupDirectory>
    with LanguageReactiveState {
  late Future<Map<String, dynamic>> directory;
  final Set<String> busy = {};
  String? adminCountry;
  late String profileCountry;
  late bool adminAccess;
  String get selectedCountry =>
      adminAccess ? adminCountry ?? profileCountry : profileCountry;
  Map<String, dynamic>? displayedDirectory;
  String? displayedCacheKey;
  int loadGeneration = 0;
  String get accessScope => [
    currentUser.role.name,
    currentUser.globalChatModerator.toString(),
  ].join(':');
  late String lastAccessScope;
  Future<Map<String, dynamic>> loadDirectory() async {
    final generation = ++loadGeneration;
    final country = selectedCountry;
    final key = GroupDirectoryCache.key(
      widget.currentUid,
      country,
      accessScope,
    );
    if (displayedCacheKey != key) {
      displayedCacheKey = key;
      displayedDirectory = GroupDirectoryCache.peek(key);
    }
    var networkFinished = false;
    unawaited(
      GroupDirectoryCache.read(key).then((saved) {
        if (!mounted ||
            generation != loadGeneration ||
            networkFinished ||
            saved == null) {
          return;
        }
        if (saved['countryCode'] != country) return;
        setState(() {
          displayedDirectory = saved;
        });
      }),
    );
    final data = await (widget.requestAction ?? privateGroupAction)({
      'action': 'directory',
      if (adminAccess) 'countryCode': country,
    });
    networkFinished = true;
    if (mounted &&
        generation == loadGeneration &&
        data['countryCode'] == country) {
      displayedDirectory = data;
      unawaited(GroupDirectoryCache.write(key, data));
    }
    return data;
  }

  void profileChanged() {
    final nextCountry = currentUserHomeCountryCode();
    final nextAdmin = currentUser.role == UserRole.admin;
    if (nextCountry == profileCountry &&
        nextAdmin == adminAccess &&
        lastAccessScope == accessScope) {
      return;
    }
    lastAccessScope = accessScope;
    profileCountry = nextCountry;
    adminAccess = nextAdmin;
    adminCountry = null;
    refresh();
  }

  @override
  void dispose() {
    currentUserProfileRevision.removeListener(profileChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    lastAccessScope = accessScope;
    profileCountry = currentUserHomeCountryCode();
    adminAccess = currentUser.role == UserRole.admin;
    currentUserProfileRevision.addListener(profileChanged);
    directory = loadDirectory();
  }

  @override
  void didUpdateWidget(covariant PrivateGroupDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membershipRevision != widget.membershipRevision ||
        oldWidget.currentUid != widget.currentUid) {
      refresh();
    }
  }

  void refresh() => setState(() {
    directory = loadDirectory();
  });

  Future<void> openGroup(Map<String, dynamic> group) async {
    final id = group['id'] as String;
    if (!busy.add(id)) return;
    setState(() {});
    try {
      if (group['isPrivate'] == false &&
          group['isMember'] != true &&
          group['isBlocked'] != true) {
        await (widget.requestAction ?? privateGroupAction)({
          'action': 'join',
          'chatId': id,
        });
        group = {...group, 'isMember': true};
        refresh();
      }
      if (group['isMember'] == true || group['canMonitor'] == true) {
        final doc = await chatsCollection()
            .doc(id)
            .get(const GetOptions(source: Source.server));
        if (!doc.exists) throw StateError('Group no longer exists.');
        if (!mounted) return;
        await Navigator.push(
          context,
          appPageRoute(
            builder: (_) => ChatConversationScreen(
              chat: ChatThreadData.fromFirestore(doc),
              readOnly: group['isMember'] != true,
            ),
          ),
        );
      } else if ((group['requestStatus'] ?? '') == '') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            icon: const Icon(Icons.group_add_outlined, color: blue),
            title: CcsText(trText('Request to join?')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  stringFromFirebase(group['name'], 'Group chat'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                CcsText(
                  trText(
                    'The group owner will receive your request. You can only request to join this group once.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: CcsText(trText('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: CcsText(trText('Request to join')),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        final result = await privateGroupAction({
          'action': 'request',
          'chatId': id,
        });
        // Persist locally too, so a failed refresh never re-enables the request.
        group['requestStatus'] = result['status'];
        await sendPushNotificationEvent({
          'type': 'group_join_request',
          'chatId': id,
        });
      }
      if (mounted) refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CcsText(trText('Could not open group. Please retry.')),
          ),
        );
      }
    } finally {
      busy.remove(id);
      if (mounted) setState(() {});
    }
  }

  Widget groupCard(Map<String, dynamic> group, String label) {
    final id = group['id'] as String;
    final member = group['isMember'] == true;
    final monitor =
        !member && group['canMonitor'] == true && group['isPrivate'] != false;
    final status = group['requestStatus'] ?? '';
    final isBusy = busy.contains(id);
    final canOpen = member || monitor;
    final canRequest =
        !canOpen &&
        group['isBlocked'] != true &&
        (group['isPrivate'] == false || status == '');
    final photoUrl = stringFromFirebase(group['photoUrl'], '').trim();
    final description = stringFromFirebase(group['description'], '').trim();
    final statusColor = status == 'rejected' ? Colors.white54 : blue;
    final fallback = const UserAvatarFallback(
      size: 58,
      icon: Icons.groups_rounded,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: panelGlass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: canOpen && !isBusy ? () => openGroup(group) : null,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: ClipOval(
                        child: isNetworkUrl(photoUrl)
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => fallback,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null ? child : fallback,
                              )
                            : fallback,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                group['isPrivate'] == false
                                    ? Icons.public
                                    : Icons.lock_outline_rounded,
                                size: 12,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: CcsText(
                                  groupVisibilityLabel(
                                    group['isPrivate'] != false,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          CcsText(
                            stringFromFirebase(group['name'], 'Group chat'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          CcsText(
                            groupMemberCountLabel(
                              intFromFirebase(group['memberCount'], 0),
                            ),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            CcsText(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (canOpen || canRequest)
                    FilledButton.icon(
                      onPressed: isBusy ? null : () => openGroup(group),
                      style: FilledButton.styleFrom(
                        backgroundColor: canRequest
                            ? blue
                            : blue.withValues(alpha: 0.12),
                        foregroundColor: canRequest ? Colors.white : blue,
                        minimumSize: Size(0, canRequest ? 32 : 40),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        padding: EdgeInsets.symmetric(
                          horizontal: canRequest ? 10 : 14,
                          vertical: canRequest ? 6 : 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: TextStyle(
                          fontSize: canRequest ? 11 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              monitor
                                  ? Icons.visibility_outlined
                                  : member
                                  ? Icons.arrow_forward_rounded
                                  : Icons.person_add_alt_1_rounded,
                              size: canRequest ? 14 : 16,
                            ),
                      label: CcsText(
                        label == 'Join group'
                            ? communityText(
                                en: 'Join group',
                                ru: 'Вступить в группу',
                                lv: 'Pievienoties grupai',
                              )
                            : trText(label),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == 'pending'
                                ? Icons.schedule_rounded
                                : Icons.lock_outline_rounded,
                            size: 15,
                            color: statusColor,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: CcsText(
                              trText(label),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (group['isOwner'] == true)
                    TextButton.icon(
                      onPressed: isBusy
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                appPageRoute(
                                  builder: (_) =>
                                      GroupJoinRequestsScreen(chatId: id),
                                ),
                              );
                              if (mounted) refresh();
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(
                        Icons.person_add_alt_1_outlined,
                        size: 16,
                      ),
                      label: CcsText(trText('Join requests')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (adminAccess)
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 180,
            child: DropdownButton<String>(
              isExpanded: true,
              value: availableCommunityCountryCodes().contains(selectedCountry)
                  ? selectedCountry
                  : null,
              hint: CcsText(trText('Select country')),
              dropdownColor: panel,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.keyboard_arrow_down, color: blue),
              items: [
                for (final code in availableCommunityCountryCodes())
                  DropdownMenuItem(
                    value: code,
                    child: CcsText(
                      localizedCountryName(code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (code) {
                if (code == null || code == selectedCountry) return;
                adminCountry = code;
                refresh();
              },
            ),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: CcsText(
              trText('Groups'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: refresh,
            tooltip: trText('Refresh'),
            icon: const Icon(Icons.refresh, color: blue),
          ),
        ],
      ),
      FutureBuilder<Map<String, dynamic>>(
        future: directory,
        builder: (context, snapshot) {
          if (displayedDirectory == null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (displayedDirectory == null && snapshot.hasError) {
            return TextButton(
              onPressed: refresh,
              child: CcsText(
                trText('Could not load private groups. Tap to retry.'),
              ),
            );
          }
          final groups = (displayedDirectory?['groups'] as List? ?? [])
              .cast<Map<String, dynamic>>();

          final publicChats = widget.chats
              .where((chat) => !chat.isPrivate)
              .toList();
          if (groups.isEmpty && publicChats.isEmpty) {
            return CcsText(
              trText('No groups yet.'),
              style: const TextStyle(color: Colors.white54),
            );
          }
          return Column(
            children: [
              if (snapshot.hasError)
                TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: CcsText(trText('Showing saved groups. Tap to retry.')),
                ),
              if (publicChats.isNotEmpty) ...[
                for (final chat in publicChats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ChatThreadTile(
                      chat: chat,
                      currentUid: widget.currentUid,
                      unreadCount: widget.unreadCountsByChatId[chat.id] ?? 0,
                    ),
                  ),
              ],
              for (final group in groups.where(
                (group) => !publicChats.any((chat) => chat.id == group['id']),
              ))
                Builder(
                  builder: (context) {
                    final member = group['isMember'] == true;
                    final monitor = !member && group['canMonitor'] == true;
                    final status = group['requestStatus'] ?? '';
                    final label = member
                        ? 'Open group'
                        : group['isBlocked'] == true
                        ? 'Request rejected'
                        : group['isPrivate'] == false
                        ? 'Join group'
                        : monitor
                        ? 'Monitor (read only)'
                        : switch (status) {
                            'pending' => 'Request pending',
                            'rejected' => 'Request rejected',
                            'accepted' => 'Request already used',
                            _ => 'Request to join',
                          };
                    return groupCard(group, label);
                  },
                ),
            ],
          );
        },
      ),
    ],
  );
}
