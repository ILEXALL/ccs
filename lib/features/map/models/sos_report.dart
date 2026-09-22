import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, timestampMillisFromFirebase;
import 'package:ccs_app/core/location/coordinates.dart'
    show safeLatLngFromFirestoreCoordinates;

class SosRequestDraft {
  final String reason;
  final String description;

  const SosRequestDraft({required this.reason, required this.description});
}

const sosReasonLabels = <String, String>{
  'battery': 'SOS reason battery',
  'tire': 'SOS reason tire',
  'fuel': 'SOS reason fuel',
  'towing': 'SOS reason towing',
  'breakdown': 'SOS reason breakdown',
  'other': 'SOS reason other',
};

const sosBlockedTextParts = <String>[
  'хуй',
  'пизд',
  'еб',
  'бля',
  'fuck',
  'shit',
  'spam',
];

bool sosDescriptionLooksLikeSpam(String value) {
  final clean = value.trim().toLowerCase();
  if (clean.length < 12) {
    return true;
  }

  final lettersAndDigits = clean.replaceAll(
    RegExp(r'[^a-zа-яё0-9]', unicode: true),
    '',
  );
  if (lettersAndDigits.length < 8) {
    return true;
  }

  final repeatedChars = RegExp(r'(.)\1{7,}', unicode: true);
  if (repeatedChars.hasMatch(clean)) {
    return true;
  }

  for (final part in sosBlockedTextParts) {
    if (clean.contains(part)) {
      return true;
    }
  }

  return false;
}

String sosReasonLabel(String reason) {
  return sosReasonLabels[reason.trim()] ?? sosReasonLabels['other']!;
}

class SosReportData {
  final String id;
  final String uid;
  final String username;
  final String description;
  final String reason;
  final LatLng coordinates;
  final int createdAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;
  final int confirmationRequestedAtMillis;
  final String status;

  const SosReportData({
    required this.id,
    required this.uid,
    required this.username,
    required this.description,
    this.reason = 'other',
    required this.coordinates,
    required this.createdAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
    this.confirmationRequestedAtMillis = 0,
    this.status = 'active',
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;
  bool get isActive => status != 'removed' && !isExpired;

  factory SosReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return SosReportData(
      id: doc.id,
      uid: stringFromFirebase(data['uid'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      description: stringFromFirebase(data['description'], ''),
      reason: stringFromFirebase(data['reason'], 'other'),
      coordinates: coordinates,
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      confirmationRequestedAtMillis: timestampMillisFromFirebase(
        data['confirmationRequestedAt'],
      ),
      status: stringFromFirebase(data['status'], 'active'),
    );
  }
}
