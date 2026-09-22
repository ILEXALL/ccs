import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class AppUser {
  final String uid;
  final String name;
  final String username;
  final String email;
  final String? photoUrl;
  final String bio;
  final String? avatarPath;
  final UserRole role;
  final bool verified;
  final bool globalChatModerator;
  final Set<String> moderatorCountryCodes;
  final String city;
  final String country;
  final bool banned;
  final int? bannedUntilMillis;
  final String banReason;

  const AppUser({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    this.photoUrl,
    this.bio = 'Find. Drive. Shoot.',
    this.avatarPath,
    required this.role,
    this.verified = false,
    this.globalChatModerator = false,
    this.moderatorCountryCodes = const <String>{},
    required this.city,
    required this.country,
    this.banned = false,
    this.bannedUntilMillis,
    this.banReason = '',
  });

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }
}
