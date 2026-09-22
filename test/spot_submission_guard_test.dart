import 'package:ccs_app/app/gates/maintenance_state.dart'
    as app
    show MaintenanceModeConfig, maintenanceModeConfig;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    as app
    show currentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' as app show AppUser;
import 'package:ccs_app/features/spots/screens/add_spot_screen.dart'
    as app
    show AddSpotScreen;
import 'package:ccs_app/features/spots/controllers/add_spot_view_state.dart'
    as app
    show AddSpotViewState;
import 'package:ccs_app/shared/models/user_role.dart' as app show UserRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final state =
          tester.state(find.byType(app.AddSpotScreen)) as app.AddSpotViewState;
      final Future<void> first = state.controller.submitSpot();
      expect(state.isSubmitting, isTrue);
      await state.controller.submitSpot();
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
