import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/data/direct_chats.dart'
    show createOrOpenDirectChat;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/community/groups/data/group_repository.dart'
    show createGroupChat;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show localizedFriendActionError;
import 'package:ccs_app/features/friends/data/friends_repository.dart'
    show loadCurrentFriendUsers;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/form_fields.dart' show CcsTextField;
import 'package:ccs_app/shared/widgets/user_avatar.dart' show UserAvatarCircle;

class NewChatScreen extends StatefulWidget {
  final bool initialGroupMode;

  const NewChatScreen({super.key, this.initialGroupMode = false});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen>
    with LanguageReactiveState {
  final searchController = TextEditingController();
  final groupNameController = TextEditingController();
  final groupDescriptionController = TextEditingController();
  final Set<String> selectedUserIds = {};
  bool groupMode = false;
  String searchText = '';
  bool isCreating = false;
  bool groupIsPrivate = false;
  String? groupAvatarLocalPath;

  @override
  void initState() {
    super.initState();
    groupMode = widget.initialGroupMode;
    searchController.addListener(() {
      setState(() => searchText = searchController.text);
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    groupNameController.dispose();
    groupDescriptionController.dispose();
    super.dispose();
  }

  bool matchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query);
  }

  Future<void> openDirectChat(FriendUserData user) async {
    setState(() => isCreating = true);

    try {
      final chatId = await createOrOpenDirectChat(user);
      final chat = ChatThreadData(
        id: chatId,
        isGroup: false,
        name: '',
        memberIds: [currentUser.uid, user.uid],
        memberUsernames: [currentUser.username, user.username],
        lastMessage: '',
        isPrivate: false,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            localizedFriendActionError(error, 'Could not open chat.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Future<void> pickGroupAvatarForNewChat() async {
    if (isCreating) {
      return;
    }

    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (path == null || path.trim().isEmpty) {
      return;
    }

    if (mounted) {
      setState(() => groupAvatarLocalPath = path);
    }
  }

  Future<void> createGroup(List<FriendUserData> friends) async {
    if (groupDescriptionController.text.trim().isEmpty ||
        groupDescriptionController.text.trim().length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: CcsText(
            communityText(
              en: 'Enter a group description (1–1000 characters).',
              ru: 'Введите описание группы (1–1000 символов).',
              lv: 'Ievadiet grupas aprakstu (1–1000 rakstzīmes).',
            ),
          ),
        ),
      );
      return;
    }
    final selected = friends
        .where((user) => selectedUserIds.contains(user.uid))
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Pick at least one friend for a group.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isCreating = true);

    try {
      final chatId = await createGroupChat(
        name: groupNameController.text,
        description: groupDescriptionController.text,
        users: selected,
        avatarLocalPath: groupAvatarLocalPath,
        isPrivate: groupIsPrivate,
      );
      final groupName = groupNameController.text.trim().isEmpty
          ? selected.map((user) => user.username).take(3).join(', ')
          : groupNameController.text.trim();
      final chat = ChatThreadData(
        id: chatId,
        isGroup: true,
        name: groupName,
        photoUrl: '',
        memberIds: [currentUser.uid, ...selected.map((user) => user.uid)],
        memberUsernames: [
          currentUser.username,
          ...selected.map((user) => user.username),
        ],
        lastMessage: '',
        isPrivate: groupIsPrivate,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not create group: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Widget userAvatar(FriendUserData user) {
    return UserAvatarCircle(user: user, size: 44);
  }

  Widget friendTile(FriendUserData user) {
    final selected = selectedUserIds.contains(user.uid);

    return InkWell(
      onTap: isCreating
          ? null
          : groupMode
          ? () {
              setState(() {
                if (selected) {
                  selectedUserIds.remove(user.uid);
                } else {
                  selectedUserIds.add(user.uid);
                }
              });
            }
          : () => openDirectChat(user),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? blue : Colors.white12,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            userAvatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    displayUsername(user.username),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
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
                        trText(user.appearsOnline ? 'online' : 'offline'),
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
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (groupMode)
              Checkbox(
                value: selected,
                onChanged: (_) {
                  setState(() {
                    if (selected) {
                      selectedUserIds.remove(user.uid);
                    } else {
                      selectedUserIds.add(user.uid);
                    }
                  });
                },
                activeColor: blue,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('New Chat'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: FutureBuilder<List<FriendUserData>>(
        future: loadCurrentFriendUsers(),
        builder: (context, snapshot) {
          final allFriends = snapshot.data ?? const <FriendUserData>[];
          final friends = groupMode
              ? [...allFriends]
              : allFriends.where(matchesSearch).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.person_outline),
                          label: CcsText('Direct'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.groups),
                          label: CcsText('Group'),
                        ),
                      ],
                      selected: {groupMode},
                      onSelectionChanged: (value) {
                        setState(() {
                          groupMode = value.first;
                          selectedUserIds.clear();
                        });
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? blue
                              : panel,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!groupMode) ...[
                const SizedBox(height: 14),
                CcsTextField(
                  controller: searchController,
                  label: 'Find friend',
                  hint: '@username',
                  icon: Icons.search,
                ),
              ],
              if (groupMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: isCreating ? null : pickGroupAvatarForNewChat,
                        borderRadius: BorderRadius.circular(999),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            ClipOval(
                              child: groupAvatarLocalPath == null
                                  ? Container(
                                      width: 58,
                                      height: 58,
                                      color: blue.withValues(alpha: 0.16),
                                      child: const Icon(
                                        Icons.groups,
                                        color: blue,
                                      ),
                                    )
                                  : Image.file(
                                      File(groupAvatarLocalPath!),
                                      width: 58,
                                      height: 58,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CcsText(
                              'Group avatar',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            CcsText(
                              'Optional. Tap to upload a photo.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: groupIsPrivate,
                      onChanged: isCreating
                          ? null
                          : (value) => setState(() => groupIsPrivate = value),
                      activeColor: blue,
                      title: const CcsText(
                        'Private group',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: const CcsText(
                        'Private groups require approval. Anyone can join a public group unless the owner has denied access.',
                        style: TextStyle(color: Colors.white54),
                      ),
                      secondary: Icon(
                        groupIsPrivate
                            ? Icons.lock_outline
                            : Icons.public_outlined,
                        color: blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CcsTextField(
                  controller: groupNameController,
                  label: 'Group name',
                  hint: 'Night drive crew',
                  icon: Icons.groups,
                ),
                TextField(
                  controller: groupDescriptionController,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: communityText(
                      en: 'Group description (required)',
                      ru: 'Описание группы (обязательно)',
                      lv: 'Grupas apraksts (obligāts)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isCreating ? null : () => createGroup(friends),
                    icon: Icon(isCreating ? Icons.hourglass_top : Icons.check),
                    label: CcsText(
                      selectedUserIds.isEmpty
                          ? 'Create Group'
                          : 'Create Group (${selectedUserIds.length + 1})',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (friends.isEmpty)
                const EmptyStateCard(
                  icon: Icons.group_outlined,
                  title: 'No friends found',
                  text: 'Add friends first, then start a chat here.',
                )
              else
                for (final friend in friends) friendTile(friend),
            ],
          );
        },
      ),
    );
  }
}
