import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/app/gates/profile_region_gate.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart';
import 'package:ccs_app/features/auth/models/app_user.dart';
import 'package:ccs_app/shared/models/user_role.dart';

AppUser profile({String uid = 'u', String city = '', String country = ''}) =>
    AppUser(
      uid: uid,
      name: 'Driver',
      username: 'driver',
      email: '',
      role: UserRole.user,
      city: city,
      country: country,
    );
void main() {
  late AppUser previous;
  setUp(() {
    previous = currentUser;
    currentUser = profile(uid: '');
  });
  tearDown(() => currentUser = previous);
  testWidgets(
    'restore error placeholder waits for profile and preserves saved region',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileRegionGate(
            loadProfile: () => pending.future,
            child: const Text('App'),
          ),
        ),
      );
      expect(find.text('Loading your profile'), findsOneWidget);
      expect(find.text('Set your region'), findsNothing);
      setCurrentUser(profile(city: 'Riga', country: 'Latvia'));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('App'), findsOneWidget);
      expect(find.text('Set your region'), findsNothing);
    },
  );
  testWidgets(
    'load failure can retry without exposing empty form or losing saved region',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileRegionGate(
            loadProfile: () async {
              if (++calls == 1)
                throw FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'unavailable',
                );
              setCurrentUser(profile(city: 'Kyiv', country: 'Ukraine'));
            },
            child: const Text('App'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(unavailable)'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-city')), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('App'), findsOneWidget);
    },
  );
  testWidgets(
    'new user selects country and saves; permission error keeps draft for retry',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileRegionGate(
            loadProfile: () async {
              setCurrentUser(profile());
            },
            saveRegion: (city, country) async {
              expect(city, 'Riga');
              expect(country, 'LV');
              if (++attempts == 1)
                throw FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'permission-denied',
                );
              setCurrentUser(profile(city: city, country: country));
            },
            child: const Text('App'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-country')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('🇱🇻 Latvia'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('🇱🇻 Latvia').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-city')),
        'Riga',
      );
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(permission-denied)'), findsOneWidget);
      expect(find.text('Riga'), findsOneWidget);
      expect(find.text('App'), findsNothing);
      await tester.ensureVisible(find.text('Save and continue'));
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
      expect(find.text('App'), findsOneWidget);
    },
  );
  testWidgets('stalled save times out with retry and keeps onboarding locked', (
    tester,
  ) async {
    currentUser = profile(country: 'Latvia');
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileRegionGate(
          loadProfile: () async {},
          operationTimeout: const Duration(seconds: 1),
          saveRegion: (_, _) => Completer<void>().future,
          child: const Text('App'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile-city')), 'Riga');
    await tester.tap(find.text('Save and continue'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save your region'), findsOneWidget);
    expect(find.text('Save and continue'), findsOneWidget);
    expect(find.text('App'), findsNothing);
  });
}
