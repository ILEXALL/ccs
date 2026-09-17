import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/main.dart' as app;

app.CarSpot event({String visibility = 'public'}) => app.CarSpot(
  id: 'event',
  name: 'Event',
  cityCountry: 'Riga, Latvia',
  countryCode: 'LV',
  coordinates: const LatLng(56.95, 24.1),
  description: 'Description',
  categories: const ['Meet'],
  photoUrl: '',
  reelLink: '',
  bestTime: '',
  parking: '',
  roadQuality: '',
  lowCarFriendly: false,
  policeRisk: '',
  traffic: '',
  lighting: '',
  crowd: '',
  addedBy: 'Creator',
  addedByUid: 'creator',
  status: app.SpotStatus.approved,
  isTemporary: true,
  startsAtMillis: 2000000000000,
  expiresAtMillis: 2000003600000,
  visibility: visibility,
  sharedGroupIds: visibility == 'group' ? ['g'] : [],
  sharedGroups: visibility == 'group'
      ? [
          {'id': 'g', 'name': 'Night Drivers', 'avatarUrl': ''},
        ]
      : [],
);
void main() {
  testWidgets(
    'Upcoming uses cyan group styling and group metadata only for group events',
    (tester) async {
      Future<void> show(String visibility) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 350,
                child: app.UpcomingTemporarySpotNewsCard(
                  spot: event(visibility: visibility),
                ),
              ),
            ),
          ),
        );
      }

      await show('group');
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Night Drivers'), findsOneWidget);
      expect(find.byType(app.GlobalSmallAvatar), findsOneWidget);
      final groupBackgrounds = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (w) =>
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xFF09252D),
          );
      expect(groupBackgrounds, hasLength(1));
      expect(
        tester
            .widget<Text>(
              find.text(event(visibility: 'group').temporaryTodayLabel),
            )
            .style
            ?.color,
        Colors.cyanAccent,
      );
      await show('public');
      expect(find.text('Group'), findsNothing);
      expect(find.text('Night Drivers'), findsNothing);
      expect(
        tester
            .widget<Text>(find.text(event().temporaryTodayLabel))
            .style
            ?.color,
        Colors.orangeAccent,
      );
    },
  );
  testWidgets(
    'membership refresh never changes a selected group audience to public',
    (tester) async {
      const group = app.ChatThreadData(
        id: 'g',
        isGroup: true,
        name: 'Night Drivers',
        memberIds: ['creator'],
        memberUsernames: ['Creator'],
        lastMessage: '',
        updatedAtMillis: 0,
      );
      app.memberSpotGroups.value = [group];
      await tester.pumpWidget(const MaterialApp(home: app.AddSpotScreen()));
      final dynamic state = tester.state(find.byType(app.AddSpotScreen));
      state.isTemporarySpot = true;
      state.groupVisibility = true;
      state.selectedGroupIds.add('g');
      // Sync restart / temporary membership failure while the form is open.
      app.memberSpotGroups.value = [];
      await tester.pump();
      expect(state.groupVisibility, isTrue);
      expect(state.selectedGroupIds, {'g'});
      app.memberSpotGroups.value = [group];
      await tester.pump();
      expect(state.groupVisibility, isTrue);
      expect(state.selectedGroupIds, {'g'});
      await tester.pumpWidget(const SizedBox());
      app.memberSpotGroups.value = [];
    },
  );
  test(
    'public is default; group audience survives edits and cache serialization',
    () {
      expect(event().isGroupSpot, isFalse);
      final spot = event(visibility: 'group');
      final edited = spot.copyWith(name: 'Edited');
      expect(edited.sharedGroupIds, ['g']);
      expect(edited.isGroupSpot, isTrue);
      final data = app.carSpotToLocalCacheData(edited);
      expect(data['visibility'], 'group');
      expect(data['sharedGroupIds'], ['g']);
      final topic = app.temporarySpotForumTopicData(
        spot: spot,
        authorId: 'creator',
        authorName: 'Creator',
        authorCountry: 'Latvia',
        authorCountryCode: 'LV',
        authorRole: app.UserRole.user,
        authorVerified: false,
        authorGlobalModerator: false,
        status: 'approved',
        reviewedBy: 'admin',
        reviewedAt: null,
        includeCreateTimestamps: false,
      );
      expect(topic['visibility'], 'group');
      expect(topic['sharedGroupIds'], ['g']);
    },
  );
  testWidgets('group labels display group name and avatar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.SpotGroupLabels(spot: event(visibility: 'group')),
        ),
      ),
    );
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Night Drivers'), findsOneWidget);
    expect(find.byType(app.GlobalSmallAvatar), findsOneWidget);
  });
}
