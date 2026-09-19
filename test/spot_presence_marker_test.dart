import 'package:ccs_app/spot_presence_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final count in [0, 1, 10]) {
    testWidgets('spot stays clickable with $count people', (tester) async {
      var spotTaps = 0;
      var peopleTaps = 0;
      const markerKey = ValueKey('spot');
      const boundsKey = ValueKey('bounds');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: boundsKey,
              width: 122 + (count > 0 ? SpotPresenceMarker.sideSpace * 2 : 0),
              height: 112,
              child: SpotPresenceMarker(
                marker: const SizedBox.expand(
                  key: markerKey,
                  child: Center(child: Icon(Icons.place)),
                ),
                onSpotTap: () => spotTaps++,
                peopleButton: count == 0
                    ? null
                    : SizedBox(
                        width: 46,
                        height: 46,
                        child: InkWell(
                          onTap: () => peopleTaps++,
                          child: Center(child: Text('$count')),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ));

      final marker = find.byKey(markerKey);
      expect(tester.getSize(marker), const Size(122, 112));
      expect(tester.getCenter(marker), tester.getCenter(find.byKey(boundsKey)));
      await tester.tap(marker);
      expect(spotTaps, 1);
      expect(peopleTaps, 0);
      if (count > 0) {
        final button = find.byType(InkWell);
        expect(tester.getRect(button).left, greaterThan(tester.getRect(marker).right));
        await tester.tap(button);
        expect(peopleTaps, 1);
        expect(spotTaps, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
