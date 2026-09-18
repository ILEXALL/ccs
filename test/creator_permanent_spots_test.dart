import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart';

void main() {
  test('creator list eligibility matches permanent spot counter', () {
    final spot = <String, dynamic>{
      'addedByUid': 'creator',
      'status': 'approved',
    };
    expect(qualifiesPermanentCreatedSpot(spot, 'creator'), isTrue);
    for (final excluded in [
      {...spot, 'isTemporary': true},
      {...spot, 'status': 'pending'},
      {...spot, 'status': 'rejected'},
      {...spot, 'deleted': true},
      {...spot, 'addedByUid': 'someone-else', 'ownerUid': 'creator'},
    ]) {
      expect(qualifiesPermanentCreatedSpot(excluded, 'creator'), isFalse);
    }
    expect(
      qualifiesPermanentCreatedSpot({
        'ownerUid': 'creator',
        'status': 'approved',
      }, 'creator'),
      isTrue,
    );
    expect(
      qualifiesPermanentCreatedSpot({
        'addedByUid': '',
        'ownerUid': 'creator',
        'status': 'approved',
      }, 'creator'),
      isTrue,
    );
  });
}
