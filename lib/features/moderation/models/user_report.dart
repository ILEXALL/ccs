import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        intFromFirebase,
        nullableTimestampMillisFromFirebase,
        stringFromFirebase;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase;

class UserReportData {
  final String id;
  final String reportedUid;
  final String reportedUsername;
  final String reportedName;
  final String reportedEmail;
  final UserRole reportedRole;
  final String reporterUid;
  final String reporterUsername;
  final String reporterEmail;
  final String reason;
  final String status;
  final int createdAtMillis;
  final String reviewedBy;

  const UserReportData({
    required this.id,
    required this.reportedUid,
    required this.reportedUsername,
    required this.reportedName,
    required this.reportedEmail,
    required this.reportedRole,
    required this.reporterUid,
    required this.reporterUsername,
    required this.reporterEmail,
    required this.reason,
    required this.status,
    required this.createdAtMillis,
    this.reviewedBy = '',
  });

  bool get isOpen => status == 'open';

  factory UserReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtMillis =
        nullableTimestampMillisFromFirebase(data['createdAt']) ??
        intFromFirebase(data['createdAtMillis'], 0);

    return UserReportData(
      id: doc.id,
      reportedUid: stringFromFirebase(data['reportedUid'], ''),
      reportedUsername: stringFromFirebase(
        data['reportedUsername'],
        'ccs_driver',
      ),
      reportedName: stringFromFirebase(data['reportedName'], 'CCS Driver'),
      reportedEmail: stringFromFirebase(data['reportedEmail'], ''),
      reportedRole: roleFromFirebase(data['reportedRole']),
      reporterUid: stringFromFirebase(data['reporterUid'], ''),
      reporterUsername: stringFromFirebase(data['reporterUsername'], 'unknown'),
      reporterEmail: stringFromFirebase(data['reporterEmail'], ''),
      reason: stringFromFirebase(data['reason'], ''),
      status: stringFromFirebase(data['status'], 'open'),
      createdAtMillis: createdAtMillis,
      reviewedBy: stringFromFirebase(data['reviewedBy'], ''),
    );
  }
}
