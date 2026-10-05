import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/core/time/trusted_clock.dart';
import 'group_temporary_spots_test.dart' show event;

void main() {
  tearDown(() => trustedClock.setSampleForTesting(null));
  test('event reveal uses server epoch time and fails closed without it', () {
    final spot = event().copyWith(
      startsAtMillis: 2000000,
      expiresAtMillis: 3000000,
      showOnMapAtMillis: 1500000,
    );
    trustedClock.setSampleForTesting(null);
    expect(spot.isTemporaryLocationAvailableNow, isFalse);
    trustedClock.setSampleForTesting(1400000);
    expect(spot.isTemporaryLocationAvailableNow, isFalse);
    trustedClock.setSampleForTesting(1600000);
    expect(spot.isTemporaryLocationAvailableNow, isTrue);
    trustedClock.setSampleForTesting(3100000);
    expect(spot.isTemporaryLocationAvailableNow, isFalse);
  });
}
