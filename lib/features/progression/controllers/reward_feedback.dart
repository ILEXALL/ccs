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
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        backgroundColor: const Color(0xFF153C62),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(data['body']?.toString() ?? 'XP credited')),
          ],
        ),
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
