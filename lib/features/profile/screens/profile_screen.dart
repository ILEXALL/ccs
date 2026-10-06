import 'package:ccs_app/features/auth/navigation/auth_pages.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show signOutCurrentAccount;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show incomingFriendRequestCountStream;
import 'package:ccs_app/features/friends/screens/blocked_users_screen.dart'
    show BlockedUsersScreen;
import 'package:ccs_app/features/friends/screens/friends_screen.dart'
    show FriendsScreen;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserHasCommunityModerationAccess;
import 'package:ccs_app/features/moderation/screens/admin_review_screen.dart'
    show AdminReviewScreen;
import 'package:ccs_app/features/moderation/screens/forum_moderation_screen.dart'
    show ForumModerationScreen;
import 'package:ccs_app/features/profile/data/profile_repository.dart'
    show saveGarageToFirebase, saveProfileToFirebase;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show garageCars;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/models/user_profile.dart'
    show UserProfileData;
import 'package:ccs_app/features/profile/screens/edit_garage_screen.dart'
    show EditGarageScreen;
import 'package:ccs_app/features/profile/screens/edit_profile_screen.dart'
    show EditProfileScreen;
import 'package:ccs_app/features/profile/screens/settings_screen.dart'
    show SettingsScreen;
import 'package:ccs_app/features/profile/widgets/garage_gallery.dart'
    show EmptyGarageCard, GarageCard;
import 'package:ccs_app/features/profile/widgets/profile_action_tile.dart'
    show ProfileActionTile;
import 'package:ccs_app/features/profile/widgets/profile_header.dart'
    show ProfileHeader;
import 'package:ccs_app/features/profile/widgets/profile_spot_previews.dart'
    show ProfileSavedSpotsPreview, ProfileSubmissionsPreview;
import 'package:ccs_app/features/progression/data/xp_access.dart'
    show canReadXpStatsForUser;
import 'package:ccs_app/features/progression/screens/xp_history_screen.dart'
    show XpHistoryScreen;
import 'package:ccs_app/features/progression/widgets/xp_summary.dart'
    show XpSummaryCard;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/creator_spots_screen.dart'
    show profileCountLabel;
import 'package:ccs_app/shared/models/countries.dart' show localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with LanguageReactiveState {
  bool isSigningOut = false;

  UserProfileData profile = UserProfileData.fromCurrentUser();
  List<GarageCar> cars = garageCars.value;

  Future<void> editProfile() async {
    final updatedProfile = await Navigator.push<UserProfileData>(
      context,
      appPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
    );

    if (!mounted || updatedProfile == null) {
      return;
    }

    try {
      await saveProfileToFirebase(updatedProfile);

      if (!mounted) {
        return;
      }

      setState(() => profile = UserProfileData.fromCurrentUser());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Profile saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not save profile: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> editGarage(int index) async {
    final updatedCar = await Navigator.push<GarageCar>(
      context,
      appPageRoute(builder: (_) => EditGarageScreen(car: cars[index])),
    );

    if (!mounted || updatedCar == null) {
      return;
    }

    final nextCars = [...cars];
    nextCars[index] = updatedCar;
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Garage saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not save garage: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> deleteCar(int index) async {
    if (index < 0 || index >= cars.length) return;
    final car = cars[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const CcsText('Delete vehicle?'),
        content: CcsText(
          'Remove ${car.name} from your garage? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const CcsText('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const CcsText('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousCars = [...cars];
    final nextCars = [...cars]..removeAt(index);
    setState(() => cars = nextCars);
    try {
      await saveGarageToFirebase(nextCars);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText('Vehicle deleted from your garage.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => cars = previousCars);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText('Could not delete vehicle: $error'),
        ),
      );
    }
  }

  Future<void> addCar() async {
    final newCar = await Navigator.push<GarageCar>(
      context,
      appPageRoute(builder: (_) => const EditGarageScreen()),
    );

    if (!mounted || newCar == null) {
      return;
    }

    final nextCars = [...cars, newCar];
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Car added to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not save car: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  void openSettings() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void openFriends() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void openXpHistory() {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? currentUser.uid.trim();

    if (uid.isEmpty || !canReadXpStatsForUser(uid)) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(builder: (_) => XpHistoryScreen(userId: uid)),
    );
  }

  void openBlacklist() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const BlockedUsersScreen()),
    );
  }

  void openAdminPanel() {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || !userRoleIsStaff(currentUser.role)) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(builder: (_) => const AdminReviewScreen()),
    );
  }

  Future<void> signOut() async {
    if (isSigningOut) {
      return;
    }

    setState(() => isSigningOut = true);

    try {
      await signOutCurrentAccount();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        appPageRoute(builder: signedOutPage),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not sign out: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningOut = false);
      }
    }
  }

  String get garageValue => profileCountLabel(cars.length);

  String get baseValue {
    final city = profile.city.trim();

    if (city.isEmpty) {
      return profile.country.trim().isEmpty
          ? trText('Unknown location')
          : localizedCountryName(profile.country);
    }

    return city;
  }

  List<String> get profileTags {
    final tags = <String>{};

    for (final car in cars) {
      tags.addAll(car.tags);
    }

    return tags.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: submittedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              if (userRoleIsStaff(currentUser.role)) ...[
                SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: openAdminPanel,
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 20,
                    ),
                    label: CcsText(
                      currentUser.role == UserRole.admin
                          ? 'Admin Panel'
                          : 'Moderator Panel',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ProfileHeader(
                profile: profile,
                garageValue: garageValue,
                spotsValue: '${spots.length} spots',
                onEdit: editProfile,
              ),
              const SizedBox(height: 12),
              XpSummaryCard(userId: currentUser.uid, onTap: openXpHistory),
              const SizedBox(height: 12),
              if (cars.isEmpty) ...[
                EmptyGarageCard(onAdd: addCar),
                const SizedBox(height: 16),
              ] else
                for (var i = 0; i < cars.length; i++) ...[
                  GarageCard(
                    car: cars[i],
                    onEdit: () => editGarage(i),
                    onDelete: () => deleteCar(i),
                  ),
                  const SizedBox(height: 16),
                ],
              ValueListenableBuilder<List<CarSpot>>(
                valueListenable: savedSpots,
                builder: (context, saved, _) {
                  return ProfileSavedSpotsPreview(spots: saved);
                },
              ),
              const SizedBox(height: 16),
              ProfileSubmissionsPreview(spots: spots),
              const SizedBox(height: 16),
              ProfileActionTile(
                icon: Icons.group_add,
                title: 'Friends',
                subtitle: 'Send requests, accept invites, and manage friends',
                badgeCountStream: incomingFriendRequestCountStream(),
                onTap: openFriends,
              ),
              const SizedBox(height: 10),
              ProfileActionTile(
                icon: Icons.block,
                title: 'Blacklist',
                subtitle: 'Manage blocked users',
                color: Colors.redAccent,
                onTap: openBlacklist,
              ),
              const SizedBox(height: 10),
              if (!userRoleIsStaff(currentUser.role))
                FutureBuilder<bool>(
                  future: currentUserHasCommunityModerationAccess(),
                  builder: (context, snapshot) {
                    if (snapshot.data != true) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProfileActionTile(
                        icon: Icons.forum_outlined,
                        title: trText('Forum moderation'),
                        subtitle: trText('Review and moderate forum topics'),
                        onTap: () {
                          Navigator.push(
                            context,
                            appPageRoute(
                              builder: (_) => const ForumModerationScreen(),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ProfileActionTile(
                icon: Icons.directions_car,
                title: 'Add another car',
                subtitle: 'Add another car to your garage',
                onTap: addCar,
              ),
              const SizedBox(height: 10),
              ProfileActionTile(
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Account, privacy, notifications',
                onTap: openSettings,
              ),
              const SizedBox(height: 10),
              ProfileActionTile(
                icon: Icons.logout,
                title: isSigningOut ? 'Signing out...' : 'Sign out',
                subtitle: 'Log out of this Google account',
                color: Colors.redAccent,
                onTap: signOut,
              ),
            ],
          );
        },
      ),
    );
  }
}
