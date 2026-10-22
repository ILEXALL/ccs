import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart';
import 'package:ccs_app/features/moderation/data/spot_review_filters.dart';
import 'package:ccs_app/features/spots/data/spot_state.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/models/spot_status.dart';
import 'package:ccs_app/shared/models/user_role.dart';
import 'spot_batch_review_test.dart' show spot;
import 'spot_review_countries_test.dart' show actor;

class SpotDocument implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'saved';
  @override
  Map<String, dynamic> data() => {
    'status': 'approved',
    'approvalMethod': 'trusted_creator',
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('saved approval method survives decoding and copyWith', () {
    final saved = CarSpot.fromFirestore(SpotDocument());
    expect(saved.isAutoApproved, isTrue);
    expect(saved.copyWith(name: 'Renamed').isAutoApproved, isTrue);
    expect(saved.copyWith(status: SpotStatus.edited).isAutoApproved, isFalse);
    expect(saved.copyWith(approvalMethod: 'manual').isAutoApproved, isFalse);
  });
  test(
    'auto approved queue distinguishes approval methods and respects country access',
    () {
      final oldUser = currentUser;
      final oldSpots = reviewSpots.value;
      addTearDown(() {
        currentUser = oldUser;
        reviewSpots.value = oldSpots;
      });
      reviewSpots.value = [
        spot('trusted').copyWith(
          status: SpotStatus.approved,
          countryCode: 'LV',
          approvalMethod: 'trusted_creator',
        ),
        spot('staff').copyWith(
          status: SpotStatus.approved,
          countryCode: 'EE',
          approvalMethod: 'staff_creation',
        ),
        spot('manual').copyWith(
          status: SpotStatus.approved,
          countryCode: 'LV',
          approvalMethod: 'manual',
        ),
        spot('legacy').copyWith(status: SpotStatus.approved, countryCode: 'LV'),
        spot('edited').copyWith(
          status: SpotStatus.edited,
          countryCode: 'LV',
          approvalMethod: 'trusted_creator',
        ),
      ];
      currentUser = actor(UserRole.admin, {});
      expect(
        adminSpotsForFilter(
          AdminSpotFilter.autoApproved,
        ).map((s) => s.id).toSet(),
        {'trusted', 'staff'},
      );
      expect(
        adminSpotCount(AdminSpotFilter.autoApproved, countryCode: 'LV'),
        1,
      );
      currentUser = actor(UserRole.moderator, {'LV'});
      expect(
        adminSpotsForFilter(AdminSpotFilter.autoApproved).single.id,
        'trusted',
      );
      expect(
        adminSpotFilterLabel(AdminSpotFilter.autoApproved),
        'Auto Approved',
      );
    },
  );
}
