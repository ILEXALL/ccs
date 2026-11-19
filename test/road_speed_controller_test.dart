import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/controllers/road_speed_controller.dart';
import 'package:ccs_app/features/map/data/road_speed_service.dart';
import 'package:ccs_app/features/map/models/road_speed.dart';
import 'package:ccs_app/features/map/widgets/road_speed_hud.dart';

class FakeTransport implements RoadSpeedTransport {
  final calls = <List<Map<String, Object?>>>[];
  final pending = <Completer<Map<String, dynamic>>>[];
  int cancelled = 0;
  @override
  Future<Map<String, dynamic>> lookup(List<Map<String, Object?>> points) {
    calls.add(points);
    final c = Completer<Map<String, dynamic>>();
    pending.add(c);
    return c.future;
  }

  @override
  void cancel() {
    cancelled++;
  }
}

Map<String, Object?> fix(int at, {double lat = 57.0, double heading = 0}) => {
  'at': at,
  'lat': lat,
  'lng': 24.0,
  'speed': 20.0,
  'accuracy': 4.0,
  'speedAccuracy': 1.0,
  'heading': heading,
  'headingAccuracy': 5.0,
  'mocked': false,
};
Map<String, dynamic> result(int at) => {
  'status': 'available',
  'kilometersPerHour': 50,
  'source': 'TomTom',
  'roadId': 'road',
  'sampleAt': at,
  'validUntil': at + 12000,
  'latitude': 57.0,
  'longitude': 24.0,
  'heading': 0.0,
  'applicabilityVerified': true,
  'unambiguousMatch': true,
};
void main() {
  test(
    'buffers GPS only during Follow, throttles and accepts fresh confirmed limit',
    () async {
      var at = 100000;
      final t = FakeTransport(), c = RoadSpeedController(FakeTransport());
      c.dispose();
      final controller = RoadSpeedController(
        t,
        now: () => DateTime.fromMillisecondsSinceEpoch(at),
      );
      addTearDown(controller.dispose);
      controller.update(fix(at), following: false);
      expect(t.calls, isEmpty);
      for (var i = 0; i < 3; i++) {
        controller.update(fix(at), following: true);
        at += 1000;
      }
      expect(t.calls.length, 1);
      expect(t.calls.single.length, 3);
      expect(controller.speedKmh, 72);
      t.pending.single.complete(result(at - 1000));
      await Future<void>.delayed(Duration.zero);
      expect(controller.limit?.kilometersPerHour, 50);
      expect(
        controller.limit!.isOverspeed(
          controller.speedKmh,
          DateTime.fromMillisecondsSinceEpoch(at),
        ),
        isTrue,
      );
      controller.update(fix(at), following: true);
      expect(t.calls.length, 1);
      controller.update(fix(at, lat: 57.001), following: true);
      expect(controller.limit, isNull);
    },
  );
  test('turns, stale and poor GPS clear limit; failure backs off', () async {
    var at = 100000;
    final t = FakeTransport();
    final c = RoadSpeedController(
      t,
      now: () => DateTime.fromMillisecondsSinceEpoch(at),
    );
    addTearDown(c.dispose);
    for (var i = 0; i < 3; i++) {
      c.update(fix(at), following: true);
      at += 1000;
    }
    t.pending.single.complete(result(at - 1000));
    await Future<void>.delayed(Duration.zero);
    c.update(fix(at, heading: 90), following: true);
    expect(c.limit, isNull);
    at += 6000;
    c.update(fix(at - 6000), following: true);
    expect(c.speedKmh, isNull);
    expect(c.limit, isNull);
    c.update({...fix(at), 'accuracy': 40.0}, following: true);
    expect(t.calls.length, 1);
    for (var i = 0; i < 3; i++) {
      c.update(fix(at), following: true);
      at += 1000;
    }
    expect(t.calls.length, 2);
    t.pending.last.complete({'status': 'unavailable', 'retryAfterSeconds': 60});
    await Future<void>.delayed(Duration.zero);
    at += 10000;
    c.update(fix(at), following: true);
    expect(t.calls.length, 2);
  });
  test(
    'exit/background cancels pending result; out-of-order and delayed data cannot restore it',
    () async {
      var at = 100000;
      final t = FakeTransport();
      final c = RoadSpeedController(
        t,
        now: () => DateTime.fromMillisecondsSinceEpoch(at),
      );
      addTearDown(c.dispose);
      for (var i = 0; i < 3; i++) {
        c.update(fix(at), following: true);
        at += 1000;
      }
      c.pause();
      expect(t.cancelled, 1);
      t.pending.single.complete(result(at - 1000));
      await Future<void>.delayed(Duration.zero);
      expect(c.limit, isNull);
      expect(c.speedKmh, isNull);
      at += 5000;
      for (var i = 0; i < 3; i++) {
        c.update(fix(at), following: true);
        at += 1000;
      }
      t.pending.last.complete(result(at - 2000));
      await Future<void>.delayed(Duration.zero);
      expect(c.limit, isNull);
    },
  );
  testWidgets('HUD shows unknown safely and colors only confirmed overspeed', (
    tester,
  ) async {
    final now = DateTime.now();
    ApplicableRoadLimit limit(DateTime expiry) => ApplicableRoadLimit(
      kilometersPerHour: 50,
      validUntil: expiry,
      source: 'TomTom',
      roadId: 'road',
      applicabilityVerified: true,
      unambiguousMatch: true,
    );
    Future<void> pump(ApplicableRoadLimit? l, double? speed) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoadSpeedHud(speedKmh: speed, limit: l),
            ),
          ),
        );
    await pump(null, 72);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('72')).style?.color,
      isNot(Colors.red),
    );
    await pump(limit(now.add(const Duration(seconds: 30))), 72);
    expect(find.text('50'), findsOneWidget);
    expect(tester.widget<Text>(find.text('72')).style?.color, Colors.red);
    await pump(limit(now.subtract(const Duration(seconds: 1))), 72);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('72')).style?.color,
      isNot(Colors.red),
    );
    await pump(null, null);
    expect(find.text('—'), findsNWidgets(2));
  });
}
