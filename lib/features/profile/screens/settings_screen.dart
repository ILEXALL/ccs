import 'dart:async';
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart';
import 'package:ccs_app/features/auth/widgets/legal_documents.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart'
    show appOutline, appPrimaryText, appSecondaryText, appSurfaceOverlay, blue;
import 'package:ccs_app/features/profile/data/profile_repository.dart'
    show saveSettingsToFirebase;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show userSettings;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/shared/widgets/form_fields.dart' show AddSpotSection;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController instagramController;
  late final TextEditingController tiktokController;
  late final TextEditingController telegramController;

  late bool reviewNotifications;
  late bool likeNotifications;
  late bool commentNotifications;
  late bool newSpotNotifications;
  late bool newMessageNotifications;
  late bool xpNotifications;
  late bool friendAtSpotNotifications;
  late bool friendLiveShareNotifications;
  late bool publicProfile;
  late bool showGarage;
  bool isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    final settings = userSettings.value;
    instagramController = TextEditingController(text: settings.instagram);
    tiktokController = TextEditingController(text: settings.tiktok);
    telegramController = TextEditingController(text: settings.telegram);
    reviewNotifications = settings.reviewNotifications;
    likeNotifications = settings.likeNotifications;
    commentNotifications = settings.commentNotifications;
    newSpotNotifications = settings.newSpotNotifications;
    newMessageNotifications = settings.newMessageNotifications;
    xpNotifications = settings.xpNotifications;
    friendAtSpotNotifications = settings.friendAtSpotNotifications;
    friendLiveShareNotifications = settings.friendLiveShareNotifications;
    publicProfile = settings.publicProfile;
    showGarage = settings.showGarage;
  }

  @override
  void dispose() {
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  UserSettingsData settingsFromForm() {
    return UserSettingsData(
      instagram: instagramController.text.trim(),
      tiktok: tiktokController.text.trim(),
      telegram: telegramController.text.trim(),
      reviewNotifications: reviewNotifications,
      likeNotifications: likeNotifications,
      commentNotifications: commentNotifications,
      newSpotNotifications: newSpotNotifications,
      newMessageNotifications: newMessageNotifications,
      xpNotifications: xpNotifications,
      friendAtSpotNotifications: friendAtSpotNotifications,
      friendLiveShareNotifications: friendLiveShareNotifications,
      publicProfile: publicProfile,
      showGarage: showGarage,
    );
  }

  Future<void> persistSettings({bool showSuccessMessage = false}) async {
    if (isSavingSettings) {
      return;
    }

    setState(() => isSavingSettings = true);

    try {
      await saveSettingsToFirebase(settingsFromForm());

      if (!mounted) {
        return;
      }

      if (showSuccessMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: CcsText(
              'Settings saved to your account.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not save settings: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSavingSettings = false);
      }
    }
  }

  Future<void> updateSettingsSwitch(VoidCallback update) async {
    setState(update);
    await persistSettings();
  }

  Future<void> saveSettings() async {
    await persistSettings(showSuccessMessage: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          const LegalDocumentLinks(),
          const DeleteAccountTile(),
          AddSpotSection(
            title: 'Notifications',
            children: [
              SettingsSwitchTile(
                icon: Icons.verified,
                title: 'Spot review updates',
                subtitle: 'Approved or rejected spot submissions',
                value: reviewNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => reviewNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.favorite,
                title: 'Likes on my spots',
                subtitle: 'When people like your approved spots',
                value: likeNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => likeNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.chat_bubble,
                title: 'Comments',
                subtitle: 'Future comments and community replies',
                value: commentNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => commentNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.map,
                title: 'New spots',
                subtitle: 'Fresh approved locations nearby',
                value: newSpotNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => newSpotNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.mark_chat_unread,
                title: 'Messages',
                subtitle: 'New direct, group and global chat messages',
                value: newMessageNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => newMessageNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.emoji_events_outlined,
                title: 'XP rewards',
                subtitle: 'When you receive XP',
                value: xpNotifications,
                onChanged: (value) =>
                    updateSettingsSwitch(() => xpNotifications = value),
              ),
              SettingsSwitchTile(
                icon: Icons.place,
                title: 'Friends at spots',
                subtitle: 'When friends stay near a spot for 5 minutes',
                value: friendAtSpotNotifications,
                onChanged: (value) => updateSettingsSwitch(
                  () => friendAtSpotNotifications = value,
                ),
              ),
              SettingsSwitchTile(
                icon: Icons.share_location,
                title: 'Friends sharing location',
                subtitle: 'When a friend starts sharing live location',
                value: friendLiveShareNotifications,
                onChanged: (value) => updateSettingsSwitch(
                  () => friendLiveShareNotifications = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Privacy',
            children: [
              SettingsSwitchTile(
                icon: Icons.public,
                title: 'Public profile',
                subtitle: 'Let other drivers see your profile',
                value: publicProfile,
                onChanged: (value) =>
                    updateSettingsSwitch(() => publicProfile = value),
              ),
              SettingsSwitchTile(
                icon: Icons.directions_car,
                title: 'Show garage',
                subtitle: 'Display your car builds on your profile',
                value: showGarage,
                onChanged: (value) =>
                    updateSettingsSwitch(() => showGarage = value),
              ),
            ],
          ),

          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSavingSettings ? null : saveSettings,
              icon: Icon(isSavingSettings ? Icons.hourglass_top : Icons.check),
              label: const CcsText('Save Settings'),
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
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appSurfaceOverlay,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: appOutline),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: blue,
        secondary: Icon(icon, color: blue),
        title: CcsText(
          trText(title),
          style: TextStyle(color: appPrimaryText, fontWeight: FontWeight.w800),
        ),
        subtitle: CcsText(
          trText(subtitle),
          style: TextStyle(color: appSecondaryText),
        ),
      ),
    );
  }
}
