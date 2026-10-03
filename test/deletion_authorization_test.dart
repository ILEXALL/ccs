import 'package:ccs_app/features/auth/data/deletion_authorization.dart';
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Provider extends Fake implements UserInfo {
  Provider(this.providerId);
  @override
  final String providerId;
}

class Token extends Fake implements IdTokenResult {
  Token({this.token = 'firebase-token', DateTime? time})
    : authTime = time ?? DateTime.now();
  @override
  final String? token;
  @override
  final DateTime? authTime;
}

class Info extends Fake implements AdditionalUserInfo {
  Info(this.authorizationCode);
  @override
  final String? authorizationCode;
}

class Credential extends Fake implements UserCredential {
  Credential(this.user, String? code) : additionalUserInfo = Info(code);
  @override
  final User? user;
  @override
  final AdditionalUserInfo? additionalUserInfo;
}

class Account extends Fake implements User {
  Account(this.events, {this.uid = 'alice', this.apple = true});
  final List<String> events;
  final bool apple;
  String? code = 'apple-one-use-code';
  Object? reauthError;
  User? returnedUser;
  IdTokenResult result = Token();
  @override
  final String uid;
  @override
  List<UserInfo> get providerData => [
    Provider(apple ? 'apple.com' : 'google.com'),
  ];
  @override
  Future<UserCredential> reauthenticateWithProvider(
    AuthProvider provider,
  ) async {
    expect(provider, isA<AppleAuthProvider>());
    events.add('reauthenticate');
    if (reauthError != null) throw reauthError!;
    return Credential(returnedUser ?? this, code);
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    expect(forceRefresh, isTrue);
    events.add('token');
    return result;
  }
}

class Auth extends Fake implements FirebaseAuth {
  Auth(this.currentUser, this.events);
  final List<String> events;
  Object? revokeError;
  @override
  User? currentUser;
  @override
  Future<void> revokeTokenWithAuthorizationCode(String code) async {
    expect(code, 'apple-one-use-code');
    events.add('revoke');
    if (revokeError != null) throw revokeError!;
  }
}

void main() {
  late List<String> events;
  late Account user;
  late Auth auth;
  setUp(() {
    events = [];
    user = Account(events);
    auth = Auth(user, events);
  });

  test(
    'Apple reauthenticates the same account and revokes before authorizing deletion',
    () async {
      expect(
        await authorizeAccountDeletion(auth: auth, user: user),
        'firebase-token',
      );
      expect(events, ['reauthenticate', 'token', 'revoke']);
    },
  );
  test('cancelling Apple confirmation never authorizes deletion', () async {
    user.reauthError = FirebaseAuthException(code: 'canceled');
    await expectLater(
      authorizeAccountDeletion(auth: auth, user: user),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(events, ['reauthenticate']);
  });
  test('missing Apple authorization code stops before revocation', () async {
    user.code = null;
    await expectLater(
      authorizeAccountDeletion(auth: auth, user: user),
      throwsStateError,
    );
    expect(events, ['reauthenticate']);
  });
  test(
    'Apple revocation failure is propagated, not treated as authorization',
    () async {
      auth.revokeError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        authorizeAccountDeletion(auth: auth, user: user),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(events, ['reauthenticate', 'token', 'revoke']);
    },
  );
  test(
    'different account returned from reauthentication is rejected',
    () async {
      user.returnedUser = Account(events, uid: 'bob');
      await expectLater(
        authorizeAccountDeletion(auth: auth, user: user),
        throwsStateError,
      );
      expect(events, ['reauthenticate']);
    },
  );
  test('a changed active session cannot authorize deletion', () async {
    auth.currentUser = Account(events, uid: 'bob');
    await expectLater(
      authorizeAccountDeletion(auth: auth, user: user),
      throwsStateError,
    );
    expect(events, ['reauthenticate']);
  });
  test('an expired non-Apple session still requires a recent login', () async {
    user = Account(events, apple: false)
      ..result = Token(
        time: DateTime.now().subtract(const Duration(minutes: 6)),
      );
    auth.currentUser = user;
    await expectLater(
      authorizeAccountDeletion(auth: auth, user: user),
      throwsStateError,
    );
    expect(events, ['token']);
  });
  test('non-Apple accounts do not invoke Apple revocation', () async {
    user = Account(events, apple: false);
    auth.currentUser = user;
    expect(
      await authorizeAccountDeletion(auth: auth, user: user),
      'firebase-token',
    );
    expect(events, ['token']);
  });
  test(
    'a missing Firebase token cannot authorize deletion or revoke Apple',
    () async {
      user.result = Token(token: null);
      await expectLater(
        authorizeAccountDeletion(auth: auth, user: user),
        throwsStateError,
      );
      expect(events, ['reauthenticate', 'token']);
    },
  );
  testWidgets(
    'cancelled Apple confirmation leaves deletion available without an error banner',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteAccountTile(
              requestDeletion: () async {
                calls++;
                throw FirebaseAuthException(code: 'canceled');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Requesting deletion…'), findsNothing);
    },
  );
}
