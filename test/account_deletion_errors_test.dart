import 'dart:async';
import 'dart:io';

import 'package:ccs_app/features/auth/data/account_deletion.dart';
import 'package:ccs_app/core/network/json_http.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deletion errors distinguish network, timeout, response and Apple failures without exposing secrets',
    () {
      expect(
        accountDeletionErrorText(TimeoutException('secret')),
        contains('may already have been received'),
      );
      expect(
        accountDeletionErrorText(const SocketException('secret')),
        contains('connect to the deletion server'),
      );
      expect(
        accountDeletionErrorText(const HandshakeException('secret')),
        contains('secure connection'),
      );
      expect(
        accountDeletionErrorText(const FormatException('secret')),
        contains('unreadable response'),
      );
      final apple = accountDeletionErrorText(
        FirebaseAuthException(code: 'invalid-credential', message: 'secret'),
      );
      expect(apple, contains('invalid-credential'));
      expect(apple, isNot(contains('secret')));
      expect(
        accountDeletionErrorText(StateError('Sign in again')),
        'Sign in again',
      );
    },
  );
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
