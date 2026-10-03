import 'package:ccs_app/features/auth/data/apple_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class TestProvider extends Fake implements UserInfo {
  TestProvider(this.providerId);
  @override
  final String providerId;
}

class TestCredential extends Fake implements UserCredential {
  TestCredential(this.user, {this.code});
  @override
  final User? user;
  final String? code;
  @override
  AdditionalUserInfo get additionalUserInfo =>
      AdditionalUserInfo(isNewUser: false, authorizationCode: code);
}

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.apple = false});
  @override
  final String uid;
  final bool apple;
  int links = 0, reloads = 0, reauths = 0;
  Object? linkError;
  String? code = 'test-authorization-code';
  User? reauthUser;
  @override
  bool get isAnonymous => false;
  @override
  List<UserInfo> get providerData => [
    TestProvider(apple ? 'apple.com' : 'google.com'),
  ];
  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) async {
    expect(provider.providerId, 'apple.com');
    links++;
    if (linkError != null) throw linkError!;
    return TestCredential(this);
  }

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<UserCredential> reauthenticateWithProvider(
    AuthProvider provider,
  ) async {
    expect(provider.providerId, 'apple.com');
    reauths++;
    return TestCredential(reauthUser ?? this, code: code);
  }
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  final User? currentUser;
  int revocations = 0;
  Object? revokeError;
  @override
  Future<void> revokeTokenWithAuthorizationCode(String code) async {
    expect(code, 'test-authorization-code');
    revocations++;
    if (revokeError != null) throw revokeError!;
  }
}

void main() {
  for (final uid in ['google-uid', 'telegram_123']) {
    test(
      'links Apple on the existing $uid without signing in to another account',
      () async {
        final user = TestUser(uid);
        final auth = TestAuth(user);
        await connectAppleToCurrentAccount(auth: auth);
        expect(auth.currentUser?.uid, uid);
        expect(user.links, 1);
        expect(user.reloads, 1);
      },
    );
  }
  test('credential collision leaves the existing account signed in', () async {
    final user = TestUser('original')
      ..linkError = FirebaseAuthException(code: 'credential-already-in-use');
    final auth = TestAuth(user);
    await expectLater(
      connectAppleToCurrentAccount(auth: auth),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.currentUser?.uid, 'original');
    expect(user.reloads, 0);
  });
  test('requires an existing session and does not relink Apple', () async {
    await expectLater(
      connectAppleToCurrentAccount(auth: TestAuth(null)),
      throwsStateError,
    );
    final user = TestUser('linked', apple: true);
    await connectAppleToCurrentAccount(auth: TestAuth(user));
    expect(user.links, 0);
  });
  test('deletion reauthenticates and revokes Apple access', () async {
    final user = TestUser('apple', apple: true);
    final auth = TestAuth(user);
    await revokeAppleForAccountDeletion(auth: auth);
    expect(user.reauths, 1);
    expect(auth.revocations, 1);
  });
  test(
    'missing authorization code or wrong account prevents revocation',
    () async {
      final user = TestUser('apple', apple: true)..code = null;
      final auth = TestAuth(user);
      await expectLater(
        revokeAppleForAccountDeletion(auth: auth),
        throwsStateError,
      );
      user.code = 'test-authorization-code';
      user.reauthUser = TestUser('other');
      await expectLater(
        revokeAppleForAccountDeletion(auth: auth),
        throwsStateError,
      );
      expect(auth.revocations, 0);
    },
  );
  test(
    'revocation failure propagates and non-Apple accounts are unaffected',
    () async {
      final auth = TestAuth(TestUser('apple', apple: true))
        ..revokeError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        revokeAppleForAccountDeletion(auth: auth),
        throwsA(isA<FirebaseAuthException>()),
      );
      final google = TestAuth(TestUser('google'));
      await revokeAppleForAccountDeletion(auth: google);
      expect(google.revocations, 0);
    },
  );
}
