import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

enum AdminSpotFilter { pending, edited, approved, rejected, all }

String adminSpotFilterLabel(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'Pending';
    case AdminSpotFilter.edited:
      return 'Edited';
    case AdminSpotFilter.approved:
      return 'Approved';
    case AdminSpotFilter.rejected:
      return 'Rejected';
    case AdminSpotFilter.all:
      return 'All';
  }
}

List<CarSpot> adminSpotsForFilter(AdminSpotFilter filter) {
  final manageableSpots = currentUser.role == UserRole.admin
      ? reviewSpots.value
      : reviewSpots.value.where(currentUserCanModerateSpot).toList();
  final spots = switch (filter) {
    AdminSpotFilter.pending =>
      manageableSpots
          .where((spot) => spot.status == SpotStatus.pending)
          .toList(),
    AdminSpotFilter.edited =>
      manageableSpots
          .where((spot) => spot.status == SpotStatus.edited)
          .toList(),
    AdminSpotFilter.approved =>
      manageableSpots
          .where((spot) => spot.status == SpotStatus.approved)
          .toList(),
    AdminSpotFilter.rejected =>
      manageableSpots
          .where((spot) => spot.status == SpotStatus.rejected)
          .toList(),
    AdminSpotFilter.all => [...manageableSpots],
  };

  int latestAdminSortMillis(CarSpot spot) {
    return spot.updatedAtMillis > 0
        ? spot.updatedAtMillis
        : spot.createdAtMillis;
  }

  spots.sort((first, second) {
    final timeCompare = latestAdminSortMillis(
      second,
    ).compareTo(latestAdminSortMillis(first));
    if (timeCompare != 0) {
      return timeCompare;
    }

    return second.createdAtMillis.compareTo(first.createdAtMillis);
  });

  return spots;
}

int adminSpotCount(AdminSpotFilter filter) {
  return adminSpotsForFilter(filter).length;
}

String adminEmptyTitle(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'No pending spots';
    case AdminSpotFilter.edited:
      return 'No edited spots';
    case AdminSpotFilter.approved:
      return 'No approved spots';
    case AdminSpotFilter.rejected:
      return 'No rejected spots';
    case AdminSpotFilter.all:
      return 'No community spots yet';
  }
}

String adminEmptyText(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'New user submitted spots will appear here first.';
    case AdminSpotFilter.edited:
      return 'User spot edits will appear here for approval.';
    case AdminSpotFilter.approved:
      return 'Approved spots will appear here after moderation.';
    case AdminSpotFilter.rejected:
      return 'Rejected spots will appear here after moderation.';
    case AdminSpotFilter.all:
      return 'When users submit spots, they will appear in this admin panel.';
  }
}
