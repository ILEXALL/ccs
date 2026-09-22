import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show inAppBadges;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show availableCommunityCountryCodes;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName;

Future<String?> showCommunityCountryPicker(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: panelGlass,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => AnimatedBuilder(
      animation: appUiPreferences,
      builder: (sheetContext, _) {
        final countries = availableCommunityCountryCodes();

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.76,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CcsText(
                          communityText(
                            en: 'Choose community country',
                            ru: 'Выберите страну сообщества',
                            lv: 'Izvēlieties kopienas valsti',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: countries.length,
                    itemBuilder: (context, index) {
                      final code = countries[index];
                      final active = code == communityCountrySelection.value;
                      return ListTile(
                        leading: CcsText(
                          countryFlagEmoji(code),
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: CcsText(
                          localizedCountryName(code),
                          style: TextStyle(
                            color: active ? blue : Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: active
                            ? const Icon(Icons.check_circle, color: blue)
                            : null,
                        onTap: () => Navigator.pop(sheetContext, code),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class CommunityCountrySelector extends StatelessWidget {
  final bool compact;

  const CommunityCountrySelector({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        communityCountrySelection,
        appUiPreferences,
      ]),
      builder: (context, _) {
        final code = communityCountrySelection.value;
        return InkWell(
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final selected = await showCommunityCountryPicker(context);
            if (selected == null || selected == code) return;
            // showModalBottomSheet completes as the route starts closing. Let
            // its inherited widgets finish deactivating before rebuilding the
            // kept-alive Global/Forum tabs for the new country.
            await Future<void>.delayed(const Duration(milliseconds: 320));
            if (!context.mounted) return;
            communityCountrySelection.value = selected;
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              unawaited(inAppBadges.start(uid, countryCode: selected));
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12,
              vertical: compact ? 6 : 9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF101722),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF253246)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CcsText(
                  countryFlagEmoji(code),
                  style: TextStyle(fontSize: compact ? 18 : 20),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: CcsText(
                    localizedCountryName(code),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 14 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  color: Colors.white54,
                  size: compact ? 17 : 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CommunityAvatarWithCountryFlag extends StatelessWidget {
  final Widget avatar;
  final String authorCountryCode;
  final String channelCountryCode;

  const CommunityAvatarWithCountryFlag({
    super.key,
    required this.avatar,
    required this.authorCountryCode,
    required this.channelCountryCode,
  });

  @override
  Widget build(BuildContext context) {
    final showFlag =
        authorCountryCode.isNotEmpty &&
        channelCountryCode.isNotEmpty &&
        authorCountryCode != channelCountryCode;
    if (!showFlag) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -5,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF111722),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white24),
            ),
            child: CcsText(
              countryFlagEmoji(authorCountryCode),
              style: const TextStyle(fontSize: 12, height: 1.05),
            ),
          ),
        ),
      ],
    );
  }
}
