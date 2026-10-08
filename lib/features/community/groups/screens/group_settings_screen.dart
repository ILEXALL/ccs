import 'package:ccs_app/core/firestore/collections.dart' show chatsCollection;
import 'package:ccs_app/features/community/groups/controllers/group_settings_view_state.dart';
import 'package:ccs_app/features/community/groups/widgets/group_settings_content.dart';
import 'package:ccs_app/features/community/groups/controllers/group_settings_controller.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show
        chatRemovalButtonLabel,
        currentUserCanLeaveGroupChat,
        currentUserOwnsGroupChat;
import 'package:ccs_app/shared/widgets/form_fields.dart' show CcsTextField;

class GroupSettingsScreen extends StatefulWidget
    implements GroupSettingsInputs {
  @override
  final ChatThreadData chat;

  final bool editMode;

  const GroupSettingsScreen({
    super.key,
    required this.chat,
    this.editMode = false,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen>
    with LanguageReactiveState
    implements GroupSettingsViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  late final GroupSettingsContentActions content = GroupSettingsContent(this);

  @override
  late final GroupSettingsControllerActions controller =
      GroupSettingsController(this);

  @override
  late final TextEditingController nameController;
  @override
  late final TextEditingController descriptionController;
  @override
  late List<String> memberIds;
  @override
  late List<String> memberUsernames;
  @override
  late List<String> memberPhotoUrls;
  @override
  late List<String> moderatorIds;
  @override
  late String ownerUid;
  @override
  late bool isPrivate;
  @override
  bool isSaving = false;
  @override
  String photoUrl = '';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.chat.name);
    descriptionController = TextEditingController(
      text: widget.chat.description,
    );
    photoUrl = widget.chat.photoUrl;
    memberIds = [...widget.chat.memberIds];
    memberUsernames = [...widget.chat.memberUsernames];
    memberPhotoUrls = [...widget.chat.memberPhotoUrls];
    moderatorIds = [...widget.chat.moderatorIds];
    ownerUid = widget.chat.effectiveOwnerUid();
    isPrivate = widget.chat.isPrivate;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> openEditor() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupSettingsScreen(chat: controller.localChatData, editMode: true),
      ),
    );
    if (!mounted) return;
    try {
      final snapshot = await chatsCollection().doc(widget.chat.id).get();
      final data = snapshot.data();
      if (!mounted || data == null) return;
      setState(() {
        nameController.text = data['name'] as String? ?? nameController.text;
        descriptionController.text =
            data['description'] as String? ?? descriptionController.text;
        photoUrl =
            data['avatarUrl'] as String? ??
            data['photoUrl'] as String? ??
            photoUrl;
        isPrivate = data['isPrivate'] as bool? ?? isPrivate;
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CcsText(trText('Could not load group. Please retry.')),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText(widget.editMode ? 'Edit group' : 'Group Info')),
        actions: [
          if (!widget.editMode && controller.canEditGroupDetails)
            IconButton(
              tooltip: trText('Edit group'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: openEditor,
            ),
        ],
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
          children: [
            if (!widget.editMode) ...[
              Center(child: content.avatarPreview()),
              const SizedBox(height: 18),
              CcsText(
                nameController.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPrivate ? Icons.lock_outline : Icons.public,
                    color: blue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  CcsText(
                    trText(isPrivate ? 'Private group' : 'Public group'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (descriptionController.text.trim().isNotEmpty) ...[
                const CcsText(
                  'About',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                CcsText(
                  descriptionController.text,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ] else ...[
              Center(
                child: InkWell(
                  onTap: controller.canEditGroupDetails && !isSaving
                      ? controller.pickGroupAvatar
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      content.avatarPreview(),
                      if (controller.canEditGroupDetails)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              AbsorbPointer(
                absorbing: !controller.canEditGroupDetails,
                child: Opacity(
                  opacity: controller.canEditGroupDetails ? 1 : 0.62,
                  child: CcsTextField(
                    controller: nameController,
                    label: trText('Group name'),
                    hint: 'Night drive crew',
                    icon: Icons.groups,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AbsorbPointer(
                absorbing: !controller.canEditGroupDetails,
                child: Opacity(
                  opacity: controller.canEditGroupDetails ? 1 : 0.62,
                  child: CcsTextField(
                    controller: descriptionController,
                    label: trText('Group description'),
                    hint: 'What is this group about?',
                    icon: Icons.info_outline,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: controller.canEditGroupDetails ? 1 : 0.62,
                child: Container(
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
                      value: isPrivate,
                      onChanged: controller.canEditGroupDetails && !isSaving
                          ? (value) => setState(() => isPrivate = value)
                          : null,
                      activeColor: blue,
                      title: const CcsText(
                        'Private group',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: const CcsText(
                        'Private groups let only the owner or staff add members.',
                        style: TextStyle(color: Colors.white54),
                      ),
                      secondary: Icon(
                        isPrivate ? Icons.lock_outline : Icons.public_outlined,
                        color: blue,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            content.membersSection(),
            const SizedBox(height: 18),
            if (widget.editMode && controller.canEditGroupDetails) ...[
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : controller.saveGroup,
                  icon: Icon(isSaving ? Icons.hourglass_top : Icons.check),
                  label: CcsText(trText('Save Group')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (currentUserCanLeaveGroupChat(controller.localChatData)) ...[
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: isSaving ? null : controller.removeGroupOrLeave,
                  icon: const Icon(Icons.logout),
                  label: CcsText(
                    chatRemovalButtonLabel(controller.localChatData),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              if (currentUserOwnsGroupChat(controller.localChatData))
                const SizedBox(height: 12),
            ],
            if (currentUserOwnsGroupChat(controller.localChatData))
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: isSaving ? null : controller.deleteGroupExplicitly,
                  icon: const Icon(Icons.delete_outline),
                  label: CcsText(
                    chatRemovalButtonLabel(
                      controller.localChatData,
                      forceDeleteGroup: true,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
