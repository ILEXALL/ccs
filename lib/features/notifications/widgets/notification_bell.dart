import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show night;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show notificationCenterUnreadCount;
import 'package:ccs_app/features/notifications/screens/notification_center_screen.dart'
    show NotificationCenterScreen;

class CcsNotificationBell extends StatelessWidget {
  const CcsNotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: trText('Notifications'),
      onPressed: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => const NotificationCenterScreen()),
        );
      },
      icon: ValueListenableBuilder<int>(
        valueListenable: notificationCenterUnreadCount,
        builder: (context, unreadCount, _) {
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(Icons.notifications_none),
              if (unreadCount > 0)
                Positioned(
                  top: -7,
                  right: -7,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: night, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: CcsText(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
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
    );
  }
}
