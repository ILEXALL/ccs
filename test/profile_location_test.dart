import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  test('first manual region selects its home community', () {
    final previousUser = app.currentUser;
    final previousCommunity = app.communityCountrySelection.value;
    addTearDown(() {
      app.currentUser = previousUser;
      app.communityCountrySelection.value = previousCommunity;
    });
    app.currentUser = const app.AppUser(
      uid: 'same-user',
      name: '',
      username: '',
      email: '',
      role: app.UserRole.user,
      city: '',
      country: '',
    );
    app.communityCountrySelection.value = 'LV';
    app.setCurrentUser(
      const app.AppUser(
        uid: 'same-user',
        name: '',
        username: '',
        email: '',
        role: app.UserRole.user,
        city: 'Moscow',
        country: 'Russia',
      ),
    );
    expect(app.communityCountrySelection.value, 'RU');
  });

  test('a valid region requires both a supported country and a city', () {
    expect(app.profileRegionIsComplete('', 'Russia'), isFalse);
    expect(app.profileRegionIsComplete('   ', 'RU'), isFalse);
    expect(app.profileRegionIsComplete('Moscow', ''), isFalse);
    expect(app.profileRegionIsComplete('Moscow', 'not a country'), isFalse);
    expect(app.profileRegionIsComplete('Moscow', 'Россия'), isTrue);
  });

  testWidgets('region popup blocks empty input, pending and failed saves', (
    tester,
  ) async {
    final previousUser = app.currentUser;
    addTearDown(() => app.currentUser = previousUser);
    app.currentUser = const app.AppUser(
      uid: 'test-user',
      name: 'Driver',
      username: 'driver',
      email: '',
      role: app.UserRole.user,
      city: '',
      country: 'Russia',
    );
    final pending = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.ProfileRegionGate(
          child: const Scaffold(body: Text('App content')),
          saveRegion: (city, country) async {
            expect(city, 'Moscow');
            expect(country, 'RU');
            attempts++;
            // Simulate the optimistic profile snapshot arriving before server ack.
            app.currentUser = const app.AppUser(
              uid: 'test-user',
              name: 'Driver',
              username: 'driver',
              email: '',
              role: app.UserRole.user,
              city: 'Moscow',
              country: 'Russia',
            );
            app.currentUserProfileRevision.value++;
            if (attempts == 1) await pending.future;
          },
        ),
      ),
    );
    expect(find.text('Set your region'), findsOneWidget);
    expect(find.text('App content'), findsNothing);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await tester.tap(find.text('Save and continue'));
    await tester.pump();
    expect(attempts, 0);
    await tester.enterText(find.byType(TextFormField), ' Moscow ');
    await tester.tap(find.text('Save and continue'));
    await tester.pump();
    expect(attempts, 1);
    expect(find.text('App content'), findsNothing);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('App content'), findsNothing);
    expect(
      find.text(
        'Could not save your region. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('App content'), findsOneWidget);
  });

  testWidgets('returning incomplete profiles stay gated after reopening', (
    tester,
  ) async {
    final previousUser = app.currentUser;
    addTearDown(() => app.currentUser = previousUser);
    app.currentUser = const app.AppUser(
      uid: 'returning',
      name: '',
      username: '',
      email: '',
      role: app.UserRole.user,
      city: 'Moscow',
      country: '',
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.pumpWidget(
        MaterialApp(
          home: app.ProfileRegionGate(
            key: ValueKey(attempt),
            child: const Text('App content'),
            saveRegion: (_, _) async {},
          ),
        ),
      );
      expect(find.text('Set your region'), findsOneWidget);
      expect(find.text('App content'), findsNothing);
    }
  });

  testWidgets('profile editor saves country and city independently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.UserProfileData? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<app.UserProfileData>(
                  MaterialPageRoute(
                    builder: (_) => const app.EditProfileScreen(
                      profile: app.UserProfileData(
                        username: 'driver',
                        city: 'Riga',
                        country: 'Latvia',
                        bio: '',
                        instagram: '',
                        tiktok: '',
                        telegram: '',
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final city = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == 'Riga',
    );
    await tester.enterText(city, 'Moscow');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final russia = find.text('🇷🇺 Russia').last;
    await tester.ensureVisible(russia);
    await tester.tap(russia);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Profile'));
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(saved?.city, 'Moscow');
    expect(saved?.country, 'Russia');
    expect(tester.takeException(), isNull);
  });

  test('automatic location prefers ISO over localized country text', () {
    final location = app.profileLocationFromPlacemark(
      const Placemark(
        locality: ' Москва ',
        country: 'Россия',
        isoCountryCode: 'RU',
      ),
    );
    expect(location, (city: 'Москва', country: 'Russia'));
  });

  test('missing geocoder data never invents Riga or Latvia', () {
    expect(app.profileLocationFromPlacemark(const Placemark()), (
      city: '',
      country: '',
    ));
    expect(app.communityAuthorCountryCode({'countryCode': 'LV'}), isEmpty);
    expect(app.communityAuthorCountryCode({'countryCode': 'RU'}), isEmpty);
  });

  test('city detection falls back to administrative area', () {
    expect(
      app.profileLocationFromPlacemark(
        const Placemark(administrativeArea: 'Moscow', country: 'Россия'),
      ),
      (city: 'Moscow', country: 'Russia'),
    );
  });

  test('author country is independent of the selected community', () {
    expect(
      app.communityAuthorCountryCode({
        'countryCode': 'RU',
        'authorCountryCode': 'LV',
        'country': 'Latvia',
      }),
      'LV',
    );
    expect(
      app.communityAuthorCountryCode({
        'countryCode': 'LV',
        'country': 'Россия',
      }),
      'RU',
    );
  });

  test('current profile corrects old message flags, unknown stays unknown', () {
    expect(app.profileAuthorCountryCode({'country': 'Russia'}, 'LV'), 'RU');
    expect(app.profileAuthorCountryCode({'country': ''}, 'LV'), isEmpty);
    expect(app.profileAuthorCountryCode({}, 'LV'), isEmpty);
    expect(app.profileAuthorCountryCode(null, 'RU'), 'RU');
  });

  test('structured profile keeps commas in city separate from country', () {
    const profile = app.UserProfileData(
      username: 'driver',
      city: 'Washington, D.C.',
      country: 'United States',
      bio: '',
      instagram: '',
      tiktok: '',
      telegram: '',
    );
    expect(profile.city, 'Washington, D.C.');
    expect(profile.country, 'United States');
    expect(profile.cityCountry, 'Washington, D.C., United States');
  });

  testWidgets('same-country and unknown authors have no foreign flag', (
    tester,
  ) async {
    for (final author in ['', 'RU']) {
      await tester.pumpWidget(
        MaterialApp(
          home: app.CommunityAvatarWithCountryFlag(
            authorCountryCode: author,
            channelCountryCode: 'RU',
            avatar: const SizedBox(width: 34, height: 34),
          ),
        ),
      );
      expect(find.text('🇱🇻'), findsNothing);
      expect(find.text('🇷🇺'), findsNothing);
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: app.CommunityAvatarWithCountryFlag(
          authorCountryCode: 'RU',
          channelCountryCode: 'LV',
          avatar: SizedBox(width: 34, height: 34),
        ),
      ),
    );
    expect(find.text('🇷🇺'), findsOneWidget);
  });
}
