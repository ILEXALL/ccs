import 'package:ccs_app/main.dart' as app;
import 'package:ccs_app/profile_city_picker.dart';
import 'package:ccs_app/startup_logo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Meta extends Fake implements SnapshotMetadata {
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

class Doc extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic> data() => {'xpTotal': 200};
  @override
  SnapshotMetadata get metadata => Meta();
}

class Ref extends Fake implements DocumentReference<Map<String, dynamic>> {
  int calls = 0;
  @override
  String get id => 'u';
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #snapshots) {
      calls++;
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.value(Doc());
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cached document listener can detach and subscribe again', () async {
    final ref = Ref();
    final stream = app.observedDocSnapshots(ref, 'regression');
    expect((await stream.first).data()?['xpTotal'], 200);
    expect((await stream.first).data()?['xpTotal'], 200);
    expect(ref.calls, 2);
  });
  test('city lookup matches country and supplies real coordinates', () async {
    final riga = await resolveProfileCity('LV', 'Riga');
    expect(riga, isNotNull);
    expect(riga!.latitude, closeTo(56.95, .1));
    expect(await resolveProfileCity('LV', 'Moscow'), isNull);
    final berlin = await resolveProfileCity('DE', 'Berlin');
    expect(berlin!.longitude, closeTo(13.4, .2));
    expect(await resolveProfileCity('LV', 'Made Up City 12345'), isNull);
  });
  testWidgets('city field requires country and is selected rather than typed', (
    tester,
  ) async {
    await tester.runAsync(() => citiesForCountry('LV'));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileCityField(countryCode: null, controller: controller),
        ),
      ),
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileCityField(countryCode: 'LV', controller: controller),
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Riga');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.title is Text &&
            (w.title as Text).data == 'Riga',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            w.title is Text &&
            (w.title as Text).data == 'Riga',
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, 'Riga');
  });
  testWidgets('startup shows a static logo on black before showing the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StartupLogo(child: Text('Ready'))),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.black,
    );
    expect(find.text('Ready'), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Ready'), findsOneWidget);
  });
}
