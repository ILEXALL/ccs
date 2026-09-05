import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart';

// A test-only snapshot double keeps these regressions independent of Firebase.
// ignore: subtype_of_sealed_class
class _ProfileSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _ProfileSnapshot(this.fields);

  final Map<String, dynamic> fields;

  @override
  String get id => 'authenticated-user';

  @override
  Map<String, dynamic> data() => fields;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('legacy profile uid cannot break the authenticated spot sync scope', () {
    for (final storedUid in ['', 'old-user', null]) {
      final user = appUserFromCurrentUserDocument(
        _ProfileSnapshot({'uid': storedUid, 'role': 'user', 'verified': true}),
      );
      expect(user.uid, 'authenticated-user');
      expect(user.verified, isTrue);
    }
  });

  test('a future map reveal does not hide an upcoming temporary spot', () {
    final now = DateTime.now();
    final spot = demoSpots.first.copyWith(
      isTemporary: true,
      startsAtMillis: now.add(const Duration(days: 2)).millisecondsSinceEpoch,
      expiresAtMillis: now.add(const Duration(days: 3)).millisecondsSinceEpoch,
      showOnMapAtMillis: now
          .add(const Duration(days: 2))
          .millisecondsSinceEpoch,
    );
    expect(spot.hasTemporaryWindow, isTrue);
    expect(spot.isVisibleNow, isTrue);
    expect(spot.isExpired, isFalse);
    expect(
      spot
          .copyWith(
            expiresAtMillis: now
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
          )
          .isVisibleNow,
      isFalse,
    );
  });
}
