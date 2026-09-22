import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

String? googleSignInSetupError;

bool firebaseReady = false;

bool rememberMeEnabled = false;

const rememberMeKey = 'remember_me';

final maintenanceAccessRevision = ValueNotifier<int>(0);

void refreshMaintenanceAccess() {
  maintenanceAccessRevision.value += 1;
}

// Global Chat and Forum share one regional channel selection. It starts from
// the signed-in user's profile country on every login; users can then read and
// post in any country that is available in the Spots/Map country filter.
final communityCountrySelection = ValueNotifier<String>('LV');

String currentUserHomeCountryCode() =>
    countryIsoCode(currentUser.country) ?? '';

// Keep the fallback unprivileged until Firebase login finishes.
AppUser currentUser = const AppUser(
  uid: '',
  name: '',
  username: '',
  email: '',
  role: UserRole.user,
  verified: false,
  globalChatModerator: false,
  city: '',
  country: '',
);

final currentUserProfileRevision = ValueNotifier<int>(0);

void setCurrentUser(AppUser value) {
  if (value.uid.isNotEmpty) {
    accountSignOutInProgress = false;
    accountSigningOut.value = false;
  }
  final previousUid = currentUser.uid;
  final previousHomeCountryCode = currentUserHomeCountryCode();
  final wasBrowsingHome =
      communityCountrySelection.value == previousHomeCountryCode;
  currentUser = value;
  if (previousUid != value.uid ||
      ((wasBrowsingHome || previousHomeCountryCode.isEmpty) &&
          previousHomeCountryCode != currentUserHomeCountryCode())) {
    communityCountrySelection.value = countryIsoCode(value.country) ?? 'LV';
  }
  refreshMaintenanceAccess();
  currentUserProfileRevision.value++;
}

bool accountSignOutInProgress = false;

final accountSigningOut = ValueNotifier<bool>(false);
