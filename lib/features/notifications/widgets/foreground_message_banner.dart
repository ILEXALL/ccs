import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ccs_app/features/progression/controllers/reward_feedback.dart'
    show rewardNavigatorKey;
import 'package:ccs_app/features/notifications/models/notification_item.dart';
import 'package:ccs_app/features/notifications/navigation/notification_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';

OverlayEntry? _entry;
Timer? _dismissTimer;
StreamSubscription<User?>? _authSubscription;
void dismissMessageBanner() {
  _dismissTimer?.cancel();
  unawaited(_authSubscription?.cancel());
  _authSubscription = null;
  _entry?.remove();
  _entry = null;
}

void showMessageBanner(NotificationCenterItem item) {
  final overlay = rewardNavigatorKey.currentState?.overlay;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (overlay == null || uid == null) return;
  dismissMessageBanner();
  _entry = OverlayEntry(
    builder: (context) => Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Material(
          elevation: 10,
          color: const Color(0xFF182D47),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              dismissMessageBanner();
              final target = rewardNavigatorKey.currentState?.overlay?.context;
              if (target != null &&
                  FirebaseAuth.instance.currentUser?.uid == uid) {
                unawaited(openNotificationCenterItem(target, item));
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.lightBlueAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: dismissMessageBanner,
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(_entry!);
  _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user?.uid != uid) dismissMessageBanner();
  });
  _dismissTimer = Timer(const Duration(seconds: 5), dismissMessageBanner);
}
