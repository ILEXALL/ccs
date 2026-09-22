import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final rewardNavigatorKey = GlobalKey<NavigatorState>();
final rewardMessengerKey = GlobalKey<ScaffoldMessengerState>();
final _seenNotifications = <String>{};
final _levels = <int>[];
bool _animatingLevel = false;
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
  if (level != null && level > 1) {
    _levels.add(level);
    unawaited(_showNextLevel());
  } else if (_lastBell == null ||
      now.difference(_lastBell!) > const Duration(seconds: 2)) {
    _lastBell = now;
    unawaited(playRewardSound('bell'));
  }
}

Future<void> _showNextLevel() async {
  if (_animatingLevel || _levels.isEmpty) return;
  final overlay = rewardNavigatorKey.currentState?.overlay;
  if (overlay == null) {
    _levels.clear();
    return;
  }
  _animatingLevel = true;
  final level = _levels.removeAt(0);
  unawaited(playRewardSound('level'));
  final entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.elasticOut,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  colors: [Color(0xFF144DA3), Color(0xFF301B64)],
                ),
                border: Border.all(color: Colors.amberAccent, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA407AFF),
                    blurRadius: 50,
                    spreadRadius: 12,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 60,
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'LEVEL UP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  Text(
                    '$level',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
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
  overlay.insert(entry);
  await Future<void>.delayed(const Duration(seconds: 3));
  entry.remove();
  _animatingLevel = false;
  unawaited(_showNextLevel());
}
