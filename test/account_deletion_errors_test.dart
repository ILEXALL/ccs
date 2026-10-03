import 'package:ccs_app/features/auth/data/account_deletion.dart';
import 'package:ccs_app/core/network/json_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server refusal is not reported as a connection failure', () {
    expect(
      accountDeletionErrorText(const JsonHttpException(503)),
      contains('on the server'),
    );
    expect(
      accountDeletionErrorText(const JsonHttpException(401)),
      contains('Sign out'),
    );
    expect(
      accountDeletionErrorText(const JsonHttpException(409)),
      contains('already exists'),
    );
  });
}
