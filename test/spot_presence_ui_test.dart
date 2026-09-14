import 'dart:io';
import 'dart:ui' as ui;
import 'package:ccs_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final language in app.AppLanguage.values) {
    testWidgets('presence counter and profile list ${language.name} fit at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 740); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      app.appUiPreferences.language = language;
      await tester.runAsync(() async {
        final font = FontLoader('PreviewFont');
        font.addFont(File('C:/Windows/Fonts/arial.ttf').readAsBytes().then(ByteData.sublistView));
        await font.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      var people = [for (var i = 0; i < 10; i++) app.LiveLocationData(uid: 'u$i', username: 'driver_$i',
        name: 'Driver $i', role: app.UserRole.user, verified: false, coordinates: const LatLng(0, 0),
        promptAtMillis: 99999999, expiresAtMillis: 99999999, updatedAtMillis: 1000)];
      String? opened;
      var taps = 0;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'PreviewFont')),
        home: RepaintBoundary(key: key, child: Scaffold(body: Column(children: [
          const SizedBox(height: 30),
          app.SpotPresenceCount(count: 10, onTap: () => taps++),
          app.SpotPeopleSheet(title: 'CCS Meet', load: () => people, onProfile: (person) => opened = person.uid),
        ])))));
      await tester.pumpAndSettle();
      expect(find.text('10'), findsOneWidget);
      await tester.tap(find.byType(app.SpotPresenceCount)); expect(taps, 1);
      await tester.tap(find.byType(ListTile).first); expect(opened, 'u0');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (language == app.AppLanguage.ru) await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/presence-previews').create(recursive: true);
        await File('build/presence-previews/people-320.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      people = [];
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ListTile), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
