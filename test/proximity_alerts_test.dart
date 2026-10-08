import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/data/proximity_alerts.dart';

void main() {
  final now = DateTime(2026, 10, 8);
  Map<String, Object> point(String kind, String id, double meters) => {
    'properties': <String, Object>{'kind': kind, 'id': id},
    'geometry': {
      'coordinates': [0.0, meters / 111195.0],
    },
  };
  ProximityAlert? check(
    ProximityAlertTracker tracker,
    String kind,
    double distance, {
    double heading = 0,
    double speed = 10,
    DateTime? at,
  }) => tracker.next(
    features: [point(kind, 'one', distance)],
    position: [0.0, 0.0],
    heading: heading,
    speed: speed,
    now: at ?? now,
  );
  test(
    'police alerts inside 500m in any direction, including when stopped',
    () {
      final tracker = ProximityAlertTracker();
      expect(check(tracker, 'police', 501), isNull);
      expect(
        check(tracker, 'police', 499, heading: 180, speed: 0)?.kind,
        'police',
      );
    },
  );
  test(
    'own police reports stay silent while nearby reports by others alert',
    () {
      final tracker = ProximityAlertTracker();
      final own = point('police', 'mine', 10);
      (own['properties'] as Map)['ownReport'] = true;
      final other = point('police', 'someone-else', 200);
      (other['properties'] as Map)['ownReport'] = false;
      ProximityAlert? next(List features) => tracker.next(
        features: features,
        position: [0.0, 0.0],
        heading: 0,
        speed: 0,
        now: now,
      );
      expect(next([own]), isNull);
      expect(next([own, other])?.key, 'police:someone-else');
      expect((own['properties'] as Map)['kind'], 'police');
    },
  );
  test('radar requires proximity, movement and a forward direction', () {
    final tracker = ProximityAlertTracker();
    expect(check(tracker, 'camera', 501), isNull);
    expect(check(tracker, 'camera', 499)?.kind, 'camera');
    expect(check(tracker, 'camera', 400, heading: 180), isNull);
    expect(check(tracker, 'camera', 400, speed: 0), isNull);
    expect(check(tracker, 'camera', 400, heading: double.nan), isNull);
  });
  test(
    'boundary jitter cannot repeat alerts; leaving then returning rearms after cooldown',
    () {
      final tracker = ProximityAlertTracker();
      tracker.markPlayed(check(tracker, 'police', 499)!, now);
      expect(check(tracker, 'police', 501), isNull);
      expect(
        check(tracker, 'police', 499, at: now.add(const Duration(minutes: 3))),
        isNull,
      );
      expect(check(tracker, 'police', 800), isNull);
      expect(
        check(tracker, 'police', 400, at: now.add(const Duration(seconds: 30))),
        isNull,
      );
      expect(
        check(tracker, 'police', 400, at: now.add(const Duration(minutes: 3))),
        isNotNull,
      );
    },
  );
  test('nearest alert first and each report has its own state', () {
    final tracker = ProximityAlertTracker();
    final features = [point('police', 'a', 450), point('camera', 'b', 250)];
    final first = tracker.next(
      features: features,
      position: [0, 0],
      heading: 0,
      speed: 10,
      now: now,
    )!;
    expect(first.key, 'camera:b');
    tracker.markPlayed(first, now);
    expect(
      tracker
          .next(
            features: features,
            position: [0, 0],
            heading: 0,
            speed: 10,
            now: now,
          )
          ?.key,
      'police:a',
    );
  });
  test('sound selection follows the requested language fallback', () {
    expect(proximitySound('police', 'ru'), 'police_RU.mp3');
    for (final language in ['en', 'lv', 'other'])
      expect(proximitySound('police', language), 'police_ENG.mp3');
    expect(proximitySound('camera', 'ru'), 'radar.mp3');
  });
}

