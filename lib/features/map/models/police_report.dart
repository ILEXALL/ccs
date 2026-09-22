import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/location/coordinates.dart'
    show safeLatLngFromFirestoreCoordinates;

class PoliceReportData {
  final String id;
  final String uid;
  final String username;
  final LatLng coordinates;
  final int createdAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;
  final String status;
  final List<String> stillThereBy;
  final List<String> notThereBy;

  const PoliceReportData({
    required this.id,
    required this.uid,
    required this.username,
    required this.coordinates,
    required this.createdAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
    this.status = 'active',
    this.stillThereBy = const [],
    this.notThereBy = const [],
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;
  bool get isActive => status != 'removed' && !isExpired;
  int get stillThereCount => stillThereBy.length;
  int get notThereCount => notThereBy.length;

  bool userPressedStillThere(String? uid) {
    return uid != null && stillThereBy.contains(uid);
  }

  bool userPressedNotThere(String? uid) {
    return uid != null && notThereBy.contains(uid);
  }

  factory PoliceReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return PoliceReportData(
      id: doc.id,
      uid: stringFromFirebase(data['uid'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      coordinates: coordinates,
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      status: stringFromFirebase(data['status'], 'active'),
      stillThereBy: stringListFromFirebase(data['stillThereBy'], const []),
      notThereBy: stringListFromFirebase(data['notThereBy'], const []),
    );
  }
}
