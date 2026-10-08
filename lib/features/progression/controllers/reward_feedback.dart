import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final rewardNavigatorKey = GlobalKey<NavigatorState>();
final rewardMessengerKey = GlobalKey<ScaffoldMessengerState>();
final _seenNotifications = <String>{};
bool levelFeedbackActive = false;
DateTime? _lastBell;

Future<void> playRewardSound(String sound) async {
  try {
    await const MethodChannel(
      'ccs/system_notifications',
    ).invokeMethod<void>('playSound', {'sound': sound});
  } on PlatformException catch (_) {
    // Feedback must not interrupt navigation if audio is unavailable.
  } on MissingPluginException catch (_) {}
}

void handleRewardNotification(
  String uid,
  String id,
  Map<String, dynamic> data,
) {
  if (!_seenNotifications.add('$uid/$id')) return;
  if (_seenNotifications.length > 1000)
    _seenNotifications.remove(_seenNotifications.first);
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
    return;
  final now = DateTime.now();
  final created = data['createdAtMillis'];
  if (created is num && now.millisecondsSinceEpoch - created > 120000) return;
  final level = (data['levelUp'] as num?)?.toInt();
  if (data['type'] == 'xp_reward') {
    rewardMessengerKey.currentState?.showSnackBar(
      SnackBar(
        // Fixed snackbars slide from the navigation edge and are clipped there.
        // Scaffold supplies the actual navigation/keyboard/safe-area offset.
        behavior: SnackBarBehavior.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 4),
        content: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF153C62),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF3979B3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, color: Color(0xFFFFD54F), size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data['body']?.toString() ?? 'XP credited',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      snackBarAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 350),
        reverseDuration: Duration(milliseconds: 300),
      ),
    );
  }
  // Level feedback is driven by authoritative XP stats, not this fresh-only
  // notification path. Do not interrupt its sound with a notification bell.
  if (levelFeedbackActive || (level != null && level > 1)) return;
  if (_lastBell == null ||
      now.difference(_lastBell!) > const Duration(seconds: 2)) {
    _lastBell = now;
    unawaited(playRewardSound('bell'));
  }
}

Future<void> stopRewardSound() async {
  try {
    await const MethodChannel(
      'ccs/system_notifications',
    ).invokeMethod<void>('stopSound');
  } on PlatformException catch (_) {
  } on MissingPluginException catch (_) {}
}
