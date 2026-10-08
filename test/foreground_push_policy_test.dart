import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/notifications/data/foreground_push_policy.dart';

void main() {
  final launch = DateTime.utc(2026, 10, 8);
  test('APNs foreground messages without a sent timestamp are displayed', () {
    expect(foregroundPushIsCurrent(null, launch), isTrue);
  });
  test(
    'new messages display while known pre-launch messages stay suppressed',
    () {
      expect(
        foregroundPushIsCurrent(launch.add(const Duration(seconds: 1)), launch),
        isTrue,
      );
      expect(
        foregroundPushIsCurrent(
          launch.subtract(const Duration(seconds: 1)),
          launch,
        ),
        isFalse,
      );
      expect(foregroundPushIsCurrent(launch, launch), isFalse);
    },
  );
}
