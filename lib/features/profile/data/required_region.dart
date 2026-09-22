import 'package:ccs_app/features/profile/models/profile_validation.dart'
    show profileRegionIsComplete;
import 'package:ccs_app/features/profile/models/profile_validation.dart'
    show requiredRegionMessage;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, setCurrentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show initializeSpotCountryFiltersForUser, spotCountryFilters;
import 'package:ccs_app/shared/models/countries.dart'
    show canonicalSpotCountryName;

Future<void> saveRequiredProfileRegion(String city, String country) async {
  if (!profileRegionIsComplete(city, country)) {
    throw ArgumentError(requiredRegionMessage);
  }
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid != currentUser.uid) {
    throw StateError('Please sign in again to save your region.');
  }
  final cleanCity = city.trim();
  final cleanCountry = canonicalSpotCountryName(country);
  await usersCollection().doc(uid).debugUpdate({
    'city': cleanCity,
    'country': cleanCountry,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  if (FirebaseAuth.instance.currentUser?.uid != uid || currentUser.uid != uid) {
    throw StateError('The signed-in account changed.');
  }
  final user = currentUser;
  setCurrentUser(
    AppUser(
      uid: user.uid,
      name: user.name,
      username: user.username,
      email: user.email,
      photoUrl: user.photoUrl,
      bio: user.bio,
      avatarPath: user.avatarPath,
      role: user.role,
      verified: user.verified,
      globalChatModerator: user.globalChatModerator,
      moderatorCountryCodes: user.moderatorCountryCodes,
      city: cleanCity,
      country: cleanCountry,
      banned: user.banned,
      bannedUntilMillis: user.bannedUntilMillis,
      banReason: user.banReason,
    ),
  );
  // A failed initial lookup may have initialized an empty country filter.
  if (spotCountryFilters.value.isEmpty) {
    await initializeSpotCountryFiltersForUser(currentUser);
  }
}
