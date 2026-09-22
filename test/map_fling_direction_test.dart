import 'package:ccs_app/features/map/widgets/exclusive_map_gestures.dart'
    show ExclusiveMapGestures;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final rotation in [0.0, 45.0, 90.0, 135.0, 270.0]) {
    for (final delta in [
      const Offset(120, 0),
      const Offset(-120, 0),
      const Offset(0, 120),
      const Offset(0, -120),
    ]) {
      testWidgets('fling $delta stays on screen axis at $rotation degrees', (
        tester,
      ) async {
        final controller = MapController();
        const origin = LatLng(56.95, 24.1);
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 400,
              height: 600,
              child: ExclusiveMapGestures(
                builder: (interactionOptions) => FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCenter: origin,
                    initialZoom: 14,
                    initialRotation: rotation,
                    interactionOptions: interactionOptions,
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
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final offset = controller.camera.latLngToScreenOffset(origin) - start;
          if (delta.dy == 0) {
            expect(offset.dy.abs(), lessThan(1.0));
            expect(offset.dx * delta.dx, greaterThan(0));
          } else {
            expect(offset.dx.abs(), lessThan(1.0));
            expect(offset.dy * delta.dy, greaterThan(0));
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }
  }
}
