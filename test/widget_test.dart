import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccs_app/main.dart';

void main() {
  testWidgets('CCS main navigation starts on Explore', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainScreen()));

    expect(find.text('Explore'), findsWidgets);
    expect(
      find.text('Approved car spots for shoots, reels, and night drives.'),
      findsOneWidget,
    );
  });
}
