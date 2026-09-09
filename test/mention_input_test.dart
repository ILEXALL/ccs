import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

app.FriendUserData user(String uid, String name) => app.FriendUserData(
  uid: uid,
  username: name,
  name: 'Profile $name',
  email: '',
  verified: false,
  role: app.UserRole.user,
  banned: false,
  deleted: false,
);

void main() {
  test('mention parser ignores emails, short tokens, and selections', () {
    TextEditingValue value(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    expect(app.activeMention(value('@j')), isNull);
    expect(app.activeMention(value('a@john')), isNull);
    expect(app.activeMention(value('@@john')), isNull);
    expect(app.activeMention(value('hello @Jo'))?.group(1), 'Jo');
    expect(app.activeMention(value('@John ')), isNull);
    expect(
      app.activeMention(
        const TextEditingValue(
          text: '@John',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
        ),
      ),
      isNull,
    );
  });

  testWidgets(
    'two-character suggestions select a user and preserve surrounding text',
    (tester) async {
      final controller = TextEditingController();
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: app.MentionTextField(
                  controller: controller,
                  currentUid: 'me',
                  loadUsers: () {
                    loads++;
                    return Stream.value([user('john', 'John')]);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hi @j');
      await tester.pump(const Duration(milliseconds: 350));
      expect(loads, 0);
      await tester.enterText(find.byType(TextField), 'Hi @jo');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('@John'), findsOneWidget);
      await tester.tap(find.text('@John'));
      await tester.pump();
      expect(controller.text, 'Hi @John ');
      expect(controller.selection.baseOffset, controller.text.length);
      expect(find.byType(ListTile), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'edit dialog suggestions stay within members and replace middle token',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertDialog(
              content: app.MentionTextField(
                controller: controller,
                currentUid: 'me',
                allowedUserIds: const ['john'],
                autofocus: true,
                loadUsers: () => Stream.value([
                  user('john', 'John'),
                  user('outsider', 'Johnny'),
                ]),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hello @joZZ later');
      controller.selection = const TextSelection.collapsed(offset: 9);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.text('@John'), findsOneWidget);
      expect(find.text('@Johnny'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('@John'));
      await tester.pump();
      expect(controller.text, 'Hello @John later');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
