import 'package:ccs_app/features/map/controllers/map_interaction_options.dart'
    as app
    show ccsMapInteractionOptions;

import 'dart:math' as math;

import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test(
    'north reset occurs once when zooming out of following, not while browsing',
    () {
      final gesture = FollowExitGesture();
      gesture.pointerDown(1, following: true, zoom: 16);
      gesture.pointerDown(2, following: false, zoom: 16);
      expect(gesture.consumeZoomOut(15.98), isFalse);
      expect(gesture.consumeZoomOut(15.8), isTrue);
      expect(gesture.consumeZoomOut(15), isFalse);
      gesture.pointerUp(1);
      gesture.pointerUp(2);
      gesture.pointerDown(3, following: false, zoom: 15);
      gesture.pointerDown(4, following: false, zoom: 15);
      expect(gesture.consumeZoomOut(13), isFalse);
      gesture.pointerUp(3);
      gesture.pointerUp(4);
      gesture.pointerDown(5, following: true, zoom: 16);
      expect(gesture.consumeZoomOut(15), isTrue);
      gesture.pointerUp(5);
    },
  );
  test('ending or cancelling a rotation discards pending follow reset', () {
    final gesture = FollowExitGesture();
    gesture.pointerDown(1, following: true, zoom: 16);
    expect(gesture.consumeZoomOut(16), isFalse);
    gesture.pointerUp(1);
    expect(gesture.consumeZoomOut(14), isFalse);
    gesture.pointerDown(2, following: false, zoom: 16);
    expect(gesture.consumeZoomOut(14), isFalse);
  });

  test('course crosses north on the short arc and ignores invalid samples', () {
    expect(interpolateCourse(350, 10, .5), 0);
    expect(interpolateCourse(10, 350, .5), 0);
    expect(interpolateCourse(90, double.nan, .5), 90);
    expect(navigationBlend(double.nan), 0);
    final frame = navigationBlend(1 / 60);
    final twoFrames = 1 - math.pow(1 - frame, 2);
    expect(twoFrames, closeTo(navigationBlend(1 / 30), 1e-9));
  });

  testWidgets('arrow points up when its course cancels camera rotation', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(56, 24),
              initialZoom: 16,
              initialRotation: -90,
            ),
            children: const [
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(56, 24),
                    width: 62,
                    height: 62,
                    rotate: false,
                    child: NavigationArrow(headingDegrees: 90),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final element = tester.element(find.byType(CustomPaint).last);
    // The arrow's local upward vector stays upward in screen coordinates.
    final box = element.findRenderObject()! as RenderBox;
    final center = box.localToGlobal(const Offset(31, 31));
    final tip = box.localToGlobal(const Offset(31, 11));
    expect(tip.dx, closeTo(center.dx, .01));
    expect(tip.dy, lessThan(center.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('rapid pinch reversals keep all camera coordinates finite', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(56.95, 24.1),
            initialZoom: 12,
            minZoom: 3,
            maxZoom: 18,
            interactionOptions: app.ccsMapInteractionOptions,
          ),
          children: const [],
        ),
      ),
    );
    await tester.pump();
    for (var round = 0; round < 5; round++) {
      final left = await tester.startGesture(
        const Offset(350, 300),
        pointer: 1,
      );
      final right = await tester.startGesture(
        const Offset(450, 300),
        pointer: 2,
      );
      for (final spread in [80.0, 180.0, 240.0, 10.0, 2.0, 100.0, 1.0, 200.0]) {
        await left.moveTo(Offset(400 - spread, 300));
        await right.moveTo(Offset(400 + spread, 300));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.camera.center.latitude.isFinite, isTrue);
        expect(controller.camera.center.longitude.isFinite, isTrue);
        expect(controller.camera.zoom.isFinite, isTrue);
        expect(tester.takeException(), isNull);
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
