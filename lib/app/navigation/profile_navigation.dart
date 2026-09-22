import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/profile/screens/public_profile_screen.dart'
    show PublicUserProfileScreen;

void navigateToUserProfile(
  BuildContext context, {
  required String uid,
  String fallbackUsername = '',
}) {
  final cleanUid = uid.trim();

  if (cleanUid.isEmpty) {
    return;
  }

  Navigator.push(
    context,
    appPageRoute(
      builder: (_) => PublicUserProfileScreen(
        userId: cleanUid,
        fallbackUsername: fallbackUsername,
      ),
    ),
  );
}
