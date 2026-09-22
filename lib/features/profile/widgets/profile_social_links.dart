import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/platform/external_links.dart'
    show launchExternalUrl;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show userSettings;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/features/profile/widgets/profile_footer.dart'
    show ProfileActionFooter;

class CompactProfileSocialLinks extends StatelessWidget {
  final Widget action;
  const CompactProfileSocialLinks({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserSettingsData>(
      valueListenable: userSettings,
      builder: (context, settings, _) {
        final links = <Widget>[
          if (settings.instagram.trim().isNotEmpty)
            CompactSocialLinkButton(
              icon: Icons.camera_alt,
              label: 'Instagram',
              value: settings.instagram,
            ),
          if (settings.tiktok.trim().isNotEmpty)
            CompactSocialLinkButton(
              icon: Icons.music_note,
              label: 'TikTok',
              value: settings.tiktok,
            ),
          if (settings.telegram.trim().isNotEmpty)
            CompactSocialLinkButton(
              icon: Icons.send,
              label: 'Telegram',
              value: settings.telegram,
            ),
        ];

        return ProfileActionFooter(action: action, links: links);
      },
    );
  }
}

class CompactSocialLinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const CompactSocialLinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        color: const Color(0xFF181A20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => launchExternalUrl(context, value.trim(), kind: label),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: label == 'Instagram' || label == 'Telegram'
                  ? Image.asset(
                      'assets/social/${label.toLowerCase()}.png',
                      width: 22,
                      height: 22,
                      excludeFromSemantics: true,
                    )
                  : Icon(icon, size: 22, color: Colors.white70),
            ),
          ),
        ),
      ),
    ),
  );
}
