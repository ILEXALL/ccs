import 'package:ccs_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile counts and Riga use the selected language', () {
    expect(app.profileCountLabel(2, language: app.AppLanguage.ru), '2 машины');
    expect(app.profileCountLabel(11, language: app.AppLanguage.ru), '11 машин');
    expect(
      app.profileCountLabel(21, language: app.AppLanguage.ru),
      '21 машина',
    );
    expect(
      app.profileCountLabel(11, spots: true, language: app.AppLanguage.ru),
      '11 спотов',
    );
    expect(app.profileCountLabel(2, language: app.AppLanguage.en), '2 cars');
    expect(app.profileCountLabel(2, language: app.AppLanguage.lv), '2 auto');
    for (final city in ['Riga', 'Рига', 'Rīga']) {
      expect(
        app.localizedProfileLocation(
          city,
          'Latvia',
          language: app.AppLanguage.ru,
        ),
        'Рига, Латвия',
      );
      expect(
        app.localizedProfileLocation(
          city,
          'Латвия',
          language: app.AppLanguage.en,
        ),
        'Riga, Latvia',
      );
      expect(
        app.localizedProfileLocation(city, 'LV', language: app.AppLanguage.lv),
        'Rīga, Latvija',
      );
    }
  });
  testWidgets('profile information stays in one compact row on narrow phones', (
    tester,
  ) async {
    for (final language in app.AppLanguage.values) {
      for (final location in [
        app.localizedProfileLocation('Riga', 'Latvia', language: language),
        'A very long city name, United Kingdom',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 288,
                child: app.ProfileInfoRow(
                  location: location,
                  cars: app.profileCountLabel(2, language: language),
                  spots: Text(
                    app.profileCountLabel(11, spots: true, language: language),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final city = find.text(location);
        final cars = find.text(app.profileCountLabel(2, language: language));
        final spots = find.text(
          app.profileCountLabel(11, spots: true, language: language),
        );
        expect(
          tester.getCenter(city).dy,
          closeTo(tester.getCenter(cars).dy, 1),
        );
        expect(
          tester.getCenter(cars).dy,
          closeTo(tester.getCenter(spots).dy, 1),
        );
        expect(
          tester.getTopLeft(city).dx,
          lessThan(tester.getTopLeft(cars).dx),
        );
        expect(
          tester.getTopLeft(cars).dx,
          lessThan(tester.getTopLeft(spots).dx),
        );
        expect(tester.widget<Icon>(find.byIcon(Icons.location_on)).size, 16);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
