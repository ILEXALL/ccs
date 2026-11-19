import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../data/road_speed_service.dart';
import '../models/road_speed.dart';

/// A short in-memory trace; never persisted. No requests outside active Follow.
class RoadSpeedController extends ChangeNotifier {
  RoadSpeedController(this.transport, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final RoadSpeedTransport transport;
  final DateTime Function() now;
  final List<Map<String, Object?>> _points = [];
  Map<String, Object?>? _latest;
  Map<String, dynamic>? _matched;
  ApplicableRoadLimit? limit;
  double? speedKmh;
  bool _busy = false, _disposed = false;
  int _generation = 0, _nextRequestAt = 0;
  static double separation(num lat1, num lng1, num lat2, num lng2) {
    const r = math.pi / 180;
    final p = (lat2 - lat1) * r, q = (lng2 - lng1) * r;
    return 12742000 *
        math.asin(
          math.min(
            1,
            math.sqrt(
              math.pow(math.sin(p / 2), 2) +
                  math.cos(lat1 * r) *
                      math.cos(lat2 * r) *
                      math.pow(math.sin(q / 2), 2),
            ),
          ),
        );
  }

  bool _quality(Map<String, Object?> p) =>
      [
        'lat',
        'lng',
        'heading',
        'headingAccuracy',
      ].every((k) => p[k] is num && (p[k] as num).isFinite) &&
      (p['lat'] as num).abs() <= 85 &&
      (p['lng'] as num).abs() <= 180 &&
      (p['heading'] as num) >= 0 &&
      (p['heading'] as num) < 360 &&
      (p['headingAccuracy'] as num) >= 0 &&
      (p['headingAccuracy'] as num) <= 20 &&
      (p['accuracy'] as num) <= 15;
  bool _stillApplies(Map<String, dynamic> result, Map<String, Object?> fix) {
    final at = result['sampleAt'],
        until = result['validUntil'],
        lat = result['latitude'],
        lng = result['longitude'],
        heading = result['heading'];
    if ([at, until, lat, lng, heading].any((v) => v is! num || !v.isFinite)) {
      return false;
    }
    final age = now().millisecondsSinceEpoch - (at as num);
    return (fix['at'] as num) >= at &&
        age >= 0 &&
        age < 12000 &&
        (until as num) > now().millisecondsSinceEpoch &&
        separation(
              lat as num,
              lng as num,
              fix['lat'] as num,
              fix['lng'] as num,
            ) <=
            10 &&
        (((fix['heading'] as num) - (heading as num) + 540) % 360 - 180)
                .abs() <=
            15;
  }

  void update(Map? raw, {required bool following}) {
    if (_disposed) return;
    if (!following) {
      pause();
      return;
    }
    final oldSpeed = speedKmh, oldLimit = limit;
    speedKmh = RoadGpsSpeed.kilometersPerHour(raw, now());
    final fix = raw == null ? null : Map<String, Object?>.from(raw);
    if (speedKmh == null || fix == null || !_quality(fix)) {
      _latest = null;
      _points.clear();
      limit = null;
      _matched = null;
      if (_busy) {
        _generation++;
        _busy = false;
        transport.cancel();
      }
    } else {
      _latest = fix;
      if (_matched != null && !_stillApplies(_matched!, fix)) {
        limit = null;
        _matched = null;
      }
      final at = (fix['at'] as num).toInt(),
          time = now().millisecondsSinceEpoch;
      _points.removeWhere((p) => time - (p['at'] as num) > 30000);
      if (_points.isNotEmpty &&
          (at < (_points.last['at'] as num) ||
              at - (_points.last['at'] as num) > 10000)) {
        _points.clear();
      }
      if (_points.isEmpty || at - (_points.last['at'] as num) >= 1000) {
        _points.add(fix);
      }
      while (_points.length > 12) {
        _points.removeAt(0);
      }
      if (!_busy &&
          time >= _nextRequestAt &&
          _points.length >= 3 &&
          at - (_points.first['at'] as num) >= 2000 &&
          speedKmh! >= 7.2) {
        _busy = true;
        _nextRequestAt = time + 5000;
        unawaited(_lookup(List.of(_points), _generation));
      }
    }
    if (oldSpeed != speedKmh || oldLimit != limit) notifyListeners();
  }

  Future<void> _lookup(
    List<Map<String, Object?>> points,
    int generation,
  ) async {
    try {
      final result = await transport.lookup(points);
      if (_disposed || generation != _generation) return;
      final retry = result['retryAfterSeconds'];
      if (result['status'] != 'available') {
        limit = null;
        _matched = null;
        _nextRequestAt =
            now().millisecondsSinceEpoch +
            (retry is num ? retry.clamp(5, 300).toInt() : 15) * 1000;
      } else {
        final n = result['kilometersPerHour'];
        final fix = _latest;
        if (fix != null &&
            _stillApplies(result, fix) &&
            n is num &&
            n.isFinite &&
            n > 0 &&
            n <= 250 &&
            result['sampleAt'] == points.last['at'] &&
            result['source'] == 'TomTom' &&
            result['roadId'] is String &&
            (result['roadId'] as String).isNotEmpty &&
            result['applicabilityVerified'] == true &&
            result['unambiguousMatch'] == true) {
          _matched = result;
          limit = ApplicableRoadLimit(
            kilometersPerHour: n.toDouble(),
            validUntil: DateTime.fromMillisecondsSinceEpoch(
              (result['validUntil'] as num).toInt(),
            ),
            source: 'TomTom',
            roadId: result['roadId'] as String,
            applicabilityVerified: true,
            unambiguousMatch: true,
          );
        } else {
          limit = null;
          _matched = null;
        }
      }
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        limit = null;
        _matched = null;
        _nextRequestAt = now().millisecondsSinceEpoch + 30000;
        notifyListeners();
      }
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  void pause() {
    final changed = speedKmh != null || limit != null;
    if (_busy || _points.isNotEmpty) {
      _generation++;
      transport.cancel();
    }
    _busy = false;
    _points.clear();
    _latest = null;
    _matched = null;
    speedKmh = null;
    limit = null;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    transport.cancel();
    super.dispose();
  }
}
