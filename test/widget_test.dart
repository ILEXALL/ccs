import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  testWidgets('main navigation stays locked until profile region is complete', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: app.MainScreen()));
    expect(find.text('Set your region'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
    expect(find.text('Save and continue'), findsOneWidget);
  });
}
