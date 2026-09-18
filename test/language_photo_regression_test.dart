import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/main.dart' as app;

class _DraftPage extends StatefulWidget {
  const _DraftPage();
  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> with app.LanguageReactiveState {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(hintText: app.trText('Search countries')),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    app.appUiPreferences.language = app.AppLanguage.en;
    app.communityCountrySelection.value = 'LV';
  });

  testWidgets('constant country selector updates EN RU LV without reopening', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: app.CommunityCountrySelector())),
    );
    for (final language in app.AppLanguage.values) {
      await app.appUiPreferences.setLanguage(language);
      await tester.pump();
      expect(find.text(app.localizedCountryName('LV')), findsOneWidget);
    }
  });

  testWidgets('computed hints change language without losing drafts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _DraftPage())),
    );
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    for (final language in app.AppLanguage.values) {
      await app.appUiPreferences.setLanguage(language);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintText, app.trText('Search countries'));
      expect(field.controller!.text, 'Keep my draft');
    }
  });

  test('wide and tall photos retain their edges with padding', () {
    for (final size in [const Size(200, 100), const Size(100, 200)]) {
      final source = img.Image(
        width: size.width.toInt(),
        height: size.height.toInt(),
      );
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      final frame = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 400,
        height: 400,
      );
      final result = app.renderFramedPhoto(source, frame);
      expect(result.width, 400);
      expect(result.height, 400);
      expect(result.getPixel(0, 0).r, 0);
      expect(result.getPixel(200, 200).r, 255);
      final redPixels = result.where((pixel) => pixel.r == 255).length;
      expect(redPixels, size.width * size.height);
    }
  });

  test('zoomed crop keeps framing and large padded output is bounded', () {
    final source = img.Image(width: 200, height: 100);
    img.fill(source, color: img.ColorRgb8(0, 255, 0));
    final crop = app.renderFramedPhoto(
      source,
      const Rect.fromLTWH(50, 25, 100, 50),
    );
    expect(crop.width, 100);
    expect(crop.height, 50);
    expect(crop.getPixel(0, 0).g, 255);
    final padded = app.renderFramedPhoto(
      source,
      const Rect.fromLTWH(-5000, -2500, 10000, 5000),
    );
    expect(padded.width, 2048);
    expect(padded.height, 1024);
  });
}
