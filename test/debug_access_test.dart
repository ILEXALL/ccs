import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  final previous = app.currentUser;
  final visible = app.firestoreDebugButtonVisible.value;
  tearDown(() {
    app.currentUser = previous;
    app.firestoreDebugButtonVisible.value = visible;
  });
  for (final role in [app.UserRole.moderator, app.UserRole.user]) {
    testWidgets('debug screen and saved toggle are denied for $role', (
      tester,
    ) async {
      app.currentUser = app.AppUser(
        uid: 'viewer',
        name: 'Viewer',
        username: 'viewer',
        email: '',
        role: role,
        country: 'Latvia',
        city: 'Riga',
      );
      app.firestoreDebugButtonVisible.value = false;
      await app.saveFirestoreDebugButtonPreference(true);
      expect(app.firestoreDebugButtonVisible.value, isFalse);
      // No Firebase setup: the denied route must not start remote reads or timers.
      await tester.pumpWidget(
        const MaterialApp(home: app.FirestoreDebugScreen()),
      );
      expect(find.text('No access'), findsOneWidget);
      expect(find.text('Firestore debug'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
