import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  testWidgets(
    'submission locks before its first await and clears on an early exit',
    (tester) async {
      final user = app.currentUser;
      final config = app.maintenanceModeConfig.value;
      addTearDown(() {
        app.currentUser = user;
        app.maintenanceModeConfig.value = config;
      });
      app.currentUser = const app.AppUser(
        uid: 'creator',
        name: 'Creator',
        username: 'creator',
        email: '',
        role: app.UserRole.user,
        city: 'Riga',
        country: 'Latvia',
      );
      app.maintenanceModeConfig.value = const app.MaintenanceModeConfig(
        maintenanceEnabled: false,
        maintenanceTitle: '',
        maintenanceMessage: '',
        allowAdminBypass: false,
        minimumAppVersion: '',
        updateContact: '',
        bannedCountryCodes: {'LV'},
      );
      await tester.pumpWidget(const MaterialApp(home: app.AddSpotScreen()));
      final dynamic state = tester.state(find.byType(app.AddSpotScreen));
      final Future<void> first = state.submitSpot();
      expect(state.isSubmitting, isTrue);
      await state.submitSpot();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await first;
      expect(state.isSubmitting, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
