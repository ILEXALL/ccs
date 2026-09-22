import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/level_up_history.dart';
import '../controllers/reward_feedback.dart';
import '../data/level_updates.dart';
import 'level_up_celebration.dart';

/// Lives inside the signed-in app, independently of the profile tab and bell.
class LevelUpFeedbackHost extends StatefulWidget {
  const LevelUpFeedbackHost({
    super.key,
    required this.userId,
    required this.child,
    this.levels,
  });

  final String userId;
  final Widget child;
  final Stream<int>? levels;

  @override
  State<LevelUpFeedbackHost> createState() => _LevelUpFeedbackHostState();
}

class _LevelUpFeedbackHostState extends State<LevelUpFeedbackHost>
    with WidgetsBindingObserver {
  StreamSubscription<int>? _subscription;
  LevelUpHistory? _history;
  OverlayEntry? _entry;
  Timer? _timer;
  int _generation = 0;
  bool _completing = false;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void didUpdateWidget(LevelUpFeedbackHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.levels != widget.levels) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _interrupt();
    _history = null;
    _completing = false;
    await _subscription?.cancel();
    _subscription = null;
    if (widget.userId.isEmpty) return;
    final uid = widget.userId;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || generation != _generation) return;
      final history = LevelUpHistory(preferences, uid);
      _history = history;
      _subscription = (widget.levels ?? watchConfirmedLevel(uid)).listen(
        (level) async {
          if (!mounted || generation != _generation) return;
          try {
            await history.observe(level);
            if (mounted && generation == _generation) _schedule();
          } catch (error) {
            debugPrint('Level feedback persistence failed: $error');
          }
        },
        onError: (Object error) =>
            debugPrint('Level feedback sync failed: $error'),
      );
      _schedule();
    } catch (error) {
      debugPrint('Level feedback initialization failed: $error');
    }
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showNext();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showNext() {
    if (!_foreground || _entry != null || _completing) return;
    final history = _history;
    final level = history?.nextLevel;
    if (history == null || level == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return; // Keep pending; never discard the queue.
    final generation = _generation;
    final entry = OverlayEntry(
      builder: (_) => LevelUpCelebration(level: level),
    );
    _entry = entry;
    levelFeedbackActive = true;
    overlay.insert(entry);
    unawaited(playRewardSound('level'));
    _timer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || generation != _generation || !_foreground) return;
      _removeEntry();
      _completing = true;
      try {
        await history.complete(level);
      } catch (error) {
        debugPrint('Level feedback acknowledgement failed: $error');
      }
      if (!mounted || generation != _generation) return;
      _completing = false;
      _schedule();
    });
  }

  void _removeEntry() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    levelFeedbackActive = false;
  }

  void _interrupt() {
    if (_entry != null) unawaited(stopRewardSound());
    _removeEntry();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
    } else {
      // Do not acknowledge an animation hidden behind another app or dialog.
      _interrupt();
    }
  }

  @override
  void dispose() {
    _generation++;
    _interrupt();
    unawaited(_subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
