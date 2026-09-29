import 'package:ccs_app/core/input/app_keyboard_dismissal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iOS toolbar reserves space above the keyboard and leaves send tappable',
    (tester) async {
      final focus = FocusNode();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var sends = 0;
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
            body: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      TextField(focusNode: focus, controller: controller),
                      const SizedBox(height: 100, child: Text('Outside')),
                      const SizedBox(height: 1200),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => sends++,
                  child: const Text('Send message'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'keep this');
      expect(focus.hasFocus, isTrue);
      expect(
        tester.getRect(find.text('Send message')).bottom,
        lessThan(tester.getRect(find.text('Done')).top),
      );
      await tester.tap(find.text('Send message'));
      expect(sends, 1);
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
