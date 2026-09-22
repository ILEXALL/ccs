import 'dart:math' as math;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show boolFromFirebase, intFromFirebase, stringFromFirebase;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show xpMaxLevel;

class XpLeaderboardEntry {
  final int rank;
  final String userId;
  final String username;
  final String name;
  final String photoUrl;
  final String avatarPath;
  final String city;
  final String country;
  final bool verified;
  final int xpTotal;
  final int weeklyXp;
  final int level;

  const XpLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.name,
    required this.photoUrl,
    required this.avatarPath,
    required this.city,
    required this.country,
    required this.verified,
    required this.xpTotal,
    required this.weeklyXp,
    required this.level,
  });

  factory XpLeaderboardEntry.fromJson(
    Map<String, dynamic> data, {
    required int fallbackRank,
  }) {
    return XpLeaderboardEntry(
      rank: math.max(1, intFromFirebase(data['rank'], fallbackRank)),
      userId: stringFromFirebase(data['userId'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], ''),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      avatarPath: stringFromFirebase(data['avatarPath'], ''),
      city: stringFromFirebase(data['city'], ''),
      country: stringFromFirebase(data['country'], ''),
      verified: boolFromFirebase(data['verified'], false),
      xpTotal: math.max(0, intFromFirebase(data['xpTotal'], 0)),
      weeklyXp: math.max(0, intFromFirebase(data['weeklyXp'], 0)),
      level: intFromFirebase(data['level'], 1).clamp(1, xpMaxLevel).toInt(),
    );
  }

  String get displayName {
    final handle = displayUsername(username);
    if (handle.isNotEmpty) {
      return handle;
    }

    return name.trim().isEmpty ? 'ccs_driver' : name.trim();
  }

  String get locationLabel {
    final cleanCity = city.trim();
    final cleanCountry = country.trim();

    if (cleanCity.isEmpty) {
      return cleanCountry;
    }

    if (cleanCountry.isEmpty) {
      return cleanCity;
    }

    return '$cleanCity, $cleanCountry';
  }
}
