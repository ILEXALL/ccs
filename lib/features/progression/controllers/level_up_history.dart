import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, account-scoped acknowledgement of completed celebrations.
/// Capturing a higher level never acknowledges it: only finishing the UI does.
class LevelUpHistory {
  LevelUpHistory(this.preferences, String uid)
    : key = 'level_feedback_v1_$uid' {
    final saved = preferences.getString(key);
    if (saved == null) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final completed = data['completed'] as int;
      final target = data['target'] as int;
      if (completed >= 1 && completed <= target && target <= 100) {
        _completed = completed;
        _target = target;
      }
    } on Object {
      // An invalid local record is re-baselined from authoritative stats.
    }
  }

  final SharedPreferences preferences;
  final String key;
  int? _completed;
  int? _target;
  Future<void> _writes = Future<void>.value();

  int? get nextLevel =>
      _completed != null && _completed! < _target! ? _completed! + 1 : null;

  Future<void> observe(int level) {
    if (level < 1 || level > 100) return Future<void>.value();
    if (_completed == null) {
      // First use establishes the existing level without replaying the whole
      // account history. Future increases survive backgrounding and restarts.
      _completed = level;
      _target = level;
    } else {
      final target = math.max(_target!, level);
      if (target == _target) return _writes;
      _target = target;
    }
    return _save();
  }

  Future<void> complete(int level) {
    if (level != nextLevel) return _writes;
    _completed = level;
    return _save();
  }

  Future<void> _save() {
    final value = jsonEncode({'completed': _completed, 'target': _target});
    // Serialize writes so a slower earlier update cannot overwrite an ack.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(key, value)) {
        throw StateError('Could not save level feedback');
      }
    });
    return _writes;
  }
}
