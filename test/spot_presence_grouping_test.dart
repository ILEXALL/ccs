import 'package:ccs_app/spot_presence_grouping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const now = 1000000;
  const origin = LatLng(0, 0);
  PresencePoint person(String id, {LatLng position = origin, int updated = now, int expires = now + 60000}) =>
      PresencePoint(id, position, updated, expires);
  test('ten visible people at a spot form one group without duplicate UIDs', () {
    final people = [for (var i = 0; i < 10; i++) person('$i'), person('0')];
    final groups = groupSpotPresence({'spot': origin}, people, now);
    expect(groups.length, 1);
    expect(groups['spot']!.length, 10);
  });
  test('overlapping radii assign each person to one nearest spot, stable on ties', () {
    final groups = groupSpotPresence({'b': origin, 'a': origin}, [person('u')], now);
    expect(groups, {'a': ['u']});
    final near = groupSpotPresence({'b': const LatLng(.0005, 0), 'a': origin},
      [person('u', position: const LatLng(.00049, 0))], now);
    expect(near, {'b': ['u']});
  });
  test('boundary, stale, expired and invalid samples cannot inflate counts', () {
    final groups = groupSpotPresence({'spot': origin}, [
      person('inside', position: LatLng(99.6 / 6371000 * 180 / pi, 0)),
      person('outside', position: LatLng(100.4 / 6371000 * 180 / pi, 0)),
      person('stale', updated: now - 150001), person('missing', updated: 0),
      person('future', updated: now + 1), person('expired', expires: now),
      person('invalid', position: LatLng(double.nan, 0)),
    ], now);
    expect(groups, {'spot': ['inside']});
  });
  test('leaving the radius immediately removes the person on the next update', () {
    expect(groupSpotPresence({'s': origin}, [person('u')], now)['s'], ['u']);
    expect(groupSpotPresence({'s': origin}, [person('u', position: const LatLng(.01, 0))], now), isEmpty);
  });
}
