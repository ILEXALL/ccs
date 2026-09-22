import 'package:flutter/widgets.dart';

// Bound by app composition before any screen is mounted.
typedef ProfileNavigation =
    void Function(
      BuildContext context, {
      required String uid,
      String fallbackUsername,
    });
late ProfileNavigation profileNavigation;
void openUserProfile(
  BuildContext context, {
  required String uid,
  String fallbackUsername = '',
}) => profileNavigation(context, uid: uid, fallbackUsername: fallbackUsername);
