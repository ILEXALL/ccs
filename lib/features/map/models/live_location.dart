import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        doubleFromFirebase,
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/location/coordinates.dart'
    show normalizedHeadingDegrees, safeLatLngFromFirestoreCoordinates;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show liveLocationStaleAfter;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, userRoleIsStaff;

class LiveLocationData {
  final bool qualityValid;
  final String uid;
  final String username;
  final String name;
  final String? photoUrl;
  final UserRole role;
  final bool verified;
  final double headingDegrees;
  final LatLng coordinates;
  final List<String> visibleToUserIds;
  final String visibleToChatId;
  final String shareScope;
  final int shareDurationMinutes;
  final int promptAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;

  const LiveLocationData({
    this.qualityValid = true,
    required this.uid,
    required this.username,
    required this.name,
    this.photoUrl,
    required this.role,
    required this.verified,
    this.headingDegrees = 0,
    required this.coordinates,
    this.visibleToUserIds = const [],
    this.visibleToChatId = '',
    this.shareScope = '',
    this.shareDurationMinutes = 60,
    required this.promptAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;

  bool get isStale {
    if (updatedAtMillis <= 0) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now - updatedAtMillis >= liveLocationStaleAfter.inMilliseconds;
  }

  bool get isActive => qualityValid && !isExpired && !isStale;

  factory LiveLocationData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    final isCurrentProfile =
        doc.id == currentUser.uid || data['uid'] == currentUser.uid;
    final role = isCurrentProfile
        ? currentUser.role
        : roleFromFirebase(data['role']);

    return LiveLocationData(
      qualityValid:
          data['isMocked'] != true &&
          (data['accuracy'] == null ||
              (data['accuracy'] is num &&
                  (data['accuracy'] as num).isFinite &&
                  (data['accuracy'] as num) >= 0 &&
                  (data['accuracy'] as num) <= 50)),
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      role: role,
      verified: userRoleIsStaff(role) || data['verified'] == true,
      headingDegrees: normalizedHeadingDegrees(
        doubleFromFirebase(data['heading'], 0),
      ),
      coordinates: coordinates,
      visibleToUserIds: stringListFromFirebase(
        data['visibleToUserIds'],
        const [],
      ),
      visibleToChatId: stringFromFirebase(data['visibleToChatId'], ''),
      shareScope: stringFromFirebase(data['shareScope'], ''),
      shareDurationMinutes: data['shareDurationMinutes'] is num
          ? (data['shareDurationMinutes'] as num).toInt()
          : 60,
      promptAtMillis: timestampMillisFromFirebase(data['promptAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: data['recordedAtMillis'] is num
          ? (data['recordedAtMillis'] as num).toInt()
          : timestampMillisFromFirebase(data['updatedAt']),
    );
  }
}
