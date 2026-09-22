import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;

Query<Map<String, dynamic>> approvedSpotsForCurrentUserQuery() {
  var query = spotsCollection()
      .where('visibility', isEqualTo: 'public')
      .where('status', isEqualTo: spotStatusName(SpotStatus.approved));

  if (!currentUserCanUseVerifiedOnlySpots) {
    query = query.where('verifiedOnly', isEqualTo: false);
  }

  return query;
}

Query<Map<String, dynamic>> activeTemporarySpotsForCurrentUserQuery() {
  var query = spotsCollection()
      .where('visibility', isEqualTo: 'public')
      .where('status', isEqualTo: spotStatusName(SpotStatus.approved))
      .where('isTemporary', isEqualTo: true);

  if (!currentUserCanUseVerifiedOnlySpots) {
    query = query.where('verifiedOnly', isEqualTo: false);
  }

  return query;
}
