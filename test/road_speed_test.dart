import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/models/road_speed.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(100000);
  Map<String, Object> fix() => {
    'at': 99000,
    'speed': 20.0,
    'accuracy': 5.0,
    'speedAccuracy': 1.0,
    'mocked': false,
  };
  test('uses real GPS speed, rejects stale and uncertain fixes', () {
    expect(RoadGpsSpeed.kilometersPerHour(fix(), now), 72);
    for (final entry in <String, Object>{
      'at': 94000,
      'speed': -1.0,
      'accuracy': 30.0,
      'speedAccuracy': 3.0,
      'mocked': true,
    }.entries) {
      expect(
        RoadGpsSpeed.kilometersPerHour({...fix(), entry.key: entry.value}, now),
        isNull,
      );
    }
    expect(RoadGpsSpeed.kilometersPerHour({...fix(), 'speed': 0.0}, now), 0);
    expect(RoadGpsSpeed.kilometersPerHour(null, now), isNull);
  });
  test('warnings require fresh resolved unambiguous limit and GPS', () {
    ApplicableRoadLimit limit({
      bool verified = true,
      bool matched = true,
      int expiry = 101000,
    }) => ApplicableRoadLimit(
      kilometersPerHour: 50,
      validUntil: DateTime.fromMillisecondsSinceEpoch(expiry),
      source: 'HERE',
      roadId: 'road',
      applicabilityVerified: verified,
      unambiguousMatch: matched,
    );
    expect(limit().isOverspeed(51, now), isTrue);
    expect(limit().isOverspeed(50, now), isFalse);
    expect(limit().isOverspeed(null, now), isFalse);
    expect(limit(verified: false).isOverspeed(90, now), isFalse);
    expect(limit(matched: false).isOverspeed(90, now), isFalse);
    expect(limit(expiry: 99000).isOverspeed(90, now), isFalse);
  });
}
