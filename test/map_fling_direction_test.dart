import 'package:ccs_app/features/map/widgets/exclusive_map_gestures.dart'
    show ExclusiveMapGestures;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
    'iOS reversal ignores release jitter and new touch stops inertia',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final controller = MapController();
      const origin = LatLng(56.95, 24.1);
      await tester.pumpWidget(
        MaterialApp(
          home: ExclusiveMapGestures(
            mapController: controller,
            builder: (options, constraint) => FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: origin,
                initialZoom: 14,
                initialRotation: 45,
                interactionOptions: options,
                cameraConstraint: constraint,
              ),
              children: const [],
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(FlutterMap));
      final finger = await tester.startGesture(center);
      for (var i = 1; i <= 6; i++) {
        await finger.moveTo(
          center + Offset(i * 20, 0),
          timeStamp: Duration(milliseconds: i * 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 1; i <= 10; i++) {
        await finger.moveTo(
          center + Offset(120 - i * 20, 0),
          timeStamp: Duration(milliseconds: 96 + i * 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The final movement is vertical noise, not a new swipe direction.
      await finger.moveTo(
        center + const Offset(-80, 1),
        timeStamp: const Duration(milliseconds: 257),
      );
      await finger.up(timeStamp: const Duration(milliseconds: 258));
      final released = controller.camera.latLngToScreenOffset(origin);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final drift = controller.camera.latLngToScreenOffset(origin) - released;
      expect(drift.dx, lessThan(-10));
      expect(drift.dy.abs(), lessThan(2));
      final interrupt = await tester.startGesture(center);
      final stopped = controller.camera.center;
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.camera.center, stopped);
      await interrupt.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final rotation in [0.0, 45.0, 90.0, 135.0, 270.0]) {
      for (final delta in [
        const Offset(120, 0),
        const Offset(-120, 0),
        const Offset(0, 120),
        const Offset(0, -120),
      ]) {
        testWidgets(
          '$platform fling $delta stays on screen axis at $rotation degrees',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            final controller = MapController();
            const origin = LatLng(56.95, 24.1);
            await tester.pumpWidget(
              MaterialApp(
                home: SizedBox(
                  width: 400,
                  height: 600,
                  child: ExclusiveMapGestures(
                    mapController: controller,
                    builder: (interactionOptions, constraint) => FlutterMap(
                      mapController: controller,
                      options: MapOptions(
                        initialCenter: origin,
                        initialZoom: 14,
                        initialRotation: rotation,
                        interactionOptions: interactionOptions,
                        cameraConstraint: constraint,
                      ),
                      children: const [],
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            final start = controller.camera.latLngToScreenOffset(origin);
            await tester.fling(find.byType(FlutterMap), delta, 2000);
            final released = controller.camera.center;
            for (var frame = 0; frame < 30; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              final offset =
                  controller.camera.latLngToScreenOffset(origin) - start;
              if (delta.dy == 0) {
                expect(offset.dy.abs(), lessThan(1.0));
                expect(offset.dx * delta.dx, greaterThan(0));
              } else {
                expect(offset.dx.abs(), lessThan(1.0));
                expect(offset.dy * delta.dy, greaterThan(0));
              }
              if (platform == TargetPlatform.iOS) {
                if (frame > 2)
                  expect(controller.camera.center, isNot(released));
              }
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }
  }
}
