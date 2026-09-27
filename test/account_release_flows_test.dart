import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart';
import 'package:ccs_app/features/auth/widgets/email_sign_in_dialog.dart';

void main() {
  testWidgets('Deletion cancel does not send a destructive request', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeleteAccountTile(
            requestDeletion: () async {
              calls++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
  testWidgets(
    'Deletion requires confirmation and prevents duplicate requests',
    (tester) async {
      var calls = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeleteAccountTile(
              requestDeletion: () {
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Requesting deletion…'));
      expect(calls, 1);
      pending.completeError(StateError('Please sign in again.'));
      await tester.pumpAndSettle();
      expect(find.text('Please sign in again.'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    },
  );
  testWidgets(
    'Email login validates input, hides password and allows failure retry',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailSignInDialog(
              signIn: (email, password) async {
                calls++;
                expect(email, 'review@example.test');
                expect(password, 'synthetic-test-password');
                throw StateError('not logged or exposed');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'review@example.test');
      await tester.enterText(fields.at(1), 'synthetic-test-password');
      expect(tester.widget<TextField>(fields.at(1)).obscureText, isTrue);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.textContaining('Check your email, password and connection.'),
        findsOneWidget,
      );
      expect(find.text('not logged or exposed'), findsNothing);
    },
  );
}
