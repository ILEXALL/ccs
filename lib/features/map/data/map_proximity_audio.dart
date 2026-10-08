import 'package:flutter/services.dart';
import 'package:ccs_app/core/localization/app_language.dart';
import 'proximity_alerts.dart';

class MapProximityAudio {
  final _tracker = ProximityAlertTracker();
  static const _channel = MethodChannel('ccs/system_notifications');
  bool _busy = false;
  int _generation = 0;
  DateTime _nextSound = DateTime(1970);

  Future<void> update(List features, Map<String, Object?>? motion) async {
    if (_busy ||
        motion == null ||
        motion['gpsFresh'] != true ||
        motion['gpsPosition'] is! List)
      return;
    final now = DateTime.now();
    final alert = _tracker.next(
      features: features,
      position: motion['gpsPosition'] as List,
      heading: (motion['heading'] as num?)?.toDouble() ?? double.nan,
      speed: (motion['speed'] as num?)?.toDouble() ?? 0,
      now: now,
    );
    if (alert == null || now.isBefore(_nextSound)) return;
    _busy = true;
    final generation = _generation;
    try {
      final sound = proximitySound(alert.kind, appUiPreferences.language.name);
      final bytes = await rootBundle.load('assets/sounds/$sound');
      if (generation != _generation) return;
      final duration = await _channel.invokeMethod<int>('playMapAlert', {
        'bytes': bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      });
      _tracker.markPlayed(alert, now);
      _nextSound = DateTime.now().add(
        Duration(milliseconds: (duration ?? 3000) + 2000),
      );
    } on PlatformException catch (_) {
      _nextSound = now.add(const Duration(seconds: 10));
    } on MissingPluginException catch (_) {
      _nextSound = now.add(const Duration(seconds: 10));
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _channel.invokeMethod<void>('stopMapAlert');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
