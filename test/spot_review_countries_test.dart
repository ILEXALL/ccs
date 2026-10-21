import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart';
import 'package:ccs_app/features/auth/models/app_user.dart';
import 'package:ccs_app/features/moderation/data/spot_review_filters.dart';
import 'package:ccs_app/features/moderation/controllers/admin_users_controller.dart';
import 'package:ccs_app/features/moderation/controllers/admin_users_view_state.dart';
import 'package:ccs_app/features/moderation/models/admin_user.dart';
import 'package:ccs_app/features/spots/data/spot_state.dart';
import 'package:ccs_app/shared/models/countries.dart';
import 'package:ccs_app/shared/models/user_role.dart';
import 'spot_batch_review_test.dart' show spot;

class Host implements AdminUsersViewState {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void enable(Set<String> codes) {
  maintenanceModeConfig.value = MaintenanceModeConfig(
    maintenanceEnabled: false,
    maintenanceTitle: '',
    maintenanceMessage: '',
    allowAdminBypass: false,
    minimumAppVersion: '',
    updateContact: '',
    bannedCountryCodes: countryNamesByIso.keys.toSet().difference(codes),
  );
}

AppUser actor(UserRole role, Set<String> countries) => AppUser(
  uid: 'staff',
  name: 'Staff',
  username: 'staff',
  email: '',
  role: role,
  country: 'Latvia',
  city: 'Riga',
  moderatorCountryCodes: countries,
);
void main() {
  setUp(() {
    final previousUser = currentUser,
        previousConfig = maintenanceModeConfig.value;
    final previousSpots = reviewSpots.value;
    addTearDown(() {
      currentUser = previousUser;
      maintenanceModeConfig.value = previousConfig;
      reviewSpots.value = previousSpots;
    });
    enable({'LV', 'EE'});
  });
  test(
    'admins see only enabled countries; moderators only enabled assignments',
    () {
      currentUser = actor(UserRole.admin, {});
      expect(adminReviewCountryCodes().toSet(), {'LV', 'EE'});
      currentUser = actor(UserRole.moderator, {'LV', 'LT'});
      expect(adminReviewCountryCodes(), ['LV']);
      enable({'EE'});
      expect(adminReviewCountryCodes(), isEmpty);
    },
  );
  test('country queues and counts never cross moderator scope', () {
    reviewSpots.value = [
      spot('lv').copyWith(countryCode: 'LV'),
      spot('ee').copyWith(countryCode: 'EE'),
    ];
    currentUser = actor(UserRole.admin, {});
    expect(adminSpotCount(AdminSpotFilter.pending, countryCode: 'LV'), 1);
    expect(
      adminSpotsForFilter(AdminSpotFilter.pending, countryCode: 'EE').single.id,
      'ee',
    );
    currentUser = actor(UserRole.moderator, {'LV'});
    expect(adminSpotCount(AdminSpotFilter.pending, countryCode: 'EE'), 0);
    expect(adminSpotCount(AdminSpotFilter.pending, countryCode: 'LV'), 1);
  });
  testWidgets(
    'assignment picker hides disabled countries and drops stale assignments',
    (tester) async {
      final controller = AdminUsersController(Host());
      Set<String>? saved;
      const user = AdminUserData(
        uid: 'u',
        username: 'u',
        name: 'U',
        email: '',
        role: UserRole.user,
        verified: false,
        banned: false,
        deleted: false,
        moderatorCountryCodes: {'LV', 'LT'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await controller.requestModeratorCountryCodes(
                    context,
                    user,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Latvia'), findsOneWidget);
      expect(find.text('Estonia'), findsOneWidget);
      expect(find.text('Lithuania'), findsNothing);
      enable({'LV'});
      await tester.pumpAndSettle();
      expect(find.text('Estonia'), findsNothing);
      await tester.tap(find.text('Save assignment'));
      await tester.pumpAndSettle();
      expect(saved, {'LV'});
      expect(tester.takeException(), isNull);
    },
  );
}
