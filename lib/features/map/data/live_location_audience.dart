import 'package:ccs_app/core/firestore/firebase_values.dart'
    show uniqueNonEmptyStrings;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show publicLiveLocationAudienceMarker;

List<String> publicLiveLocationVisibleToUserIds(String uid) {
  return uniqueNonEmptyStrings([uid, publicLiveLocationAudienceMarker]);
}
