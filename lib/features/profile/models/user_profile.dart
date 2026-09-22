import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show userSettings;

class UserProfileData {
  final String username;
  final String city;
  final String country;
  String get cityCountry =>
      [city.trim(), country.trim()].where((part) => part.isNotEmpty).join(', ');
  final String bio;
  final String instagram;
  final String tiktok;
  final String telegram;
  final String? avatarPath;
  final String? photoUrl;

  const UserProfileData({
    required this.username,
    required this.city,
    required this.country,
    required this.bio,
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    this.avatarPath,
    this.photoUrl,
  });

  factory UserProfileData.fromCurrentUser() {
    final settings = userSettings.value;

    return UserProfileData(
      username: currentUser.username,
      city: currentUser.city,
      country: currentUser.country,
      bio: currentUser.bio,
      instagram: settings.instagram,
      tiktok: settings.tiktok,
      telegram: settings.telegram,
      avatarPath: currentUser.avatarPath,
      photoUrl: currentUser.photoUrl,
    );
  }
}
