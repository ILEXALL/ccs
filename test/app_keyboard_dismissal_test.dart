import 'package:ccs_app/core/input/app_keyboard_dismissal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iOS outside tap, drag and Done dismiss without breaking editing',
    (tester) async {
      final focus = FocusNode();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: const EdgeInsets.only(bottom: 200)),
            child: AppKeyboardDismissal(child: child!),
          ),
          home: Scaffold(
            body: ListView(
              children: [
                TextField(focusNode: focus, controller: controller),
                const SizedBox(height: 100, child: Text('Outside')),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'keep this');
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('Outside'));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(controller.text, 'keep this');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
