import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, night;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show notificationCenterUnreadCount;
import 'package:ccs_app/features/notifications/screens/notification_center_screen.dart'
    show NotificationCenterScreen;

class SpotsHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const SpotsHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(icon, color: blue, size: 20),
          ),
        ),
      ),
    );
  }
}

class SpotsHeaderLanguageButton extends StatelessWidget {
  const SpotsHeaderLanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return PopupMenuButton<AppLanguage>(
          tooltip: trText('Language'),
          onSelected: (language) {
            unawaited(appUiPreferences.setLanguage(language));
          },
          itemBuilder: (context) => [
            for (final language in AppLanguage.values)
              PopupMenuItem<AppLanguage>(
                value: language,
                child: Row(
                  children: [
                    Icon(
                      appUiPreferences.language == language
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: blue,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    CcsText(language.name.toUpperCase()),
                  ],
                ),
              ),
          ],
          child: Container(
            width: 42,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: blue.withValues(alpha: 0.38)),
            ),
            child: CcsText(
              appUiPreferences.language.name.toUpperCase(),
              style: const TextStyle(
                color: blue,
                fontSize: 10.5,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

class SpotsHeaderNotificationButton extends StatelessWidget {
  const SpotsHeaderNotificationButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: trText('Notifications'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              appPageRoute(builder: (_) => const NotificationCenterScreen()),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: notificationCenterUnreadCount,
              builder: (context, unreadCount, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_none, color: blue, size: 21),
                    if (unreadCount > 0)
                      Positioned(
                        top: -7,
                        right: -8,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: night, width: 1.2),
                          ),
                          child: CcsText(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
