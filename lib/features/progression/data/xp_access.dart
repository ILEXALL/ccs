import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;

bool canReadXpStatsForUser(String userId) {
  final cleanUserId = userId.trim();
  final currentUid =
      FirebaseAuth.instance.currentUser?.uid.trim() ?? currentUser.uid.trim();

  return cleanUserId.isNotEmpty &&
      currentUid.isNotEmpty &&
      (cleanUserId == currentUid || userRoleIsStaff(currentUser.role));
}
