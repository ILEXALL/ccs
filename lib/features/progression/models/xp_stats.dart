import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show xpLevelFromTotal, xpMaxLevel, xpRequiredForLevel;

class XpUserStats {
  final String userId;
  final int xpTotal;
  final int level;
  final int weeklyXp;
  final String weeklyXpWeek;
  final bool xpBlocked;
  final String xpLastTransactionId;

  const XpUserStats({
    required this.userId,
    required this.xpTotal,
    required this.level,
    required this.weeklyXp,
    required this.weeklyXpWeek,
    required this.xpBlocked,
    required this.xpLastTransactionId,
  });

  factory XpUserStats.empty(String userId) {
    return XpUserStats(
      userId: userId,
      xpTotal: 0,
      level: 1,
      weeklyXp: 0,
      weeklyXpWeek: '',
      xpBlocked: false,
      xpLastTransactionId: '',
    );
  }

  factory XpUserStats.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final xpTotal = math.max(0, intFromFirebase(data['xpTotal'], 0));
    final rawLevel = intFromFirebase(data['level'], xpLevelFromTotal(xpTotal));

    return XpUserStats(
      userId: stringFromFirebase(data['userId'], doc.id),
      xpTotal: xpTotal,
      level: rawLevel.clamp(1, xpMaxLevel).toInt(),
      weeklyXp: math.max(0, intFromFirebase(data['weeklyXp'], 0)),
      weeklyXpWeek: stringFromFirebase(data['weeklyXpWeek'], ''),
      xpBlocked: data['xpBlocked'] == true,
      xpLastTransactionId: stringFromFirebase(data['xpLastTransactionId'], ''),
    );
  }

  bool get hasXp => xpTotal > 0 || weeklyXp > 0;

  int get currentLevelXp => xpRequiredForLevel(level);

  int get nextLevel => level >= xpMaxLevel ? xpMaxLevel : level + 1;

  int get nextLevelXp => xpRequiredForLevel(nextLevel);

  int get remainingToNextLevel {
    if (level >= xpMaxLevel) {
      return 0;
    }

    return math.max(0, nextLevelXp - xpTotal);
  }

  double get progressToNextLevel {
    if (level >= xpMaxLevel) {
      return 1;
    }

    final levelRange = nextLevelXp - currentLevelXp;
    if (levelRange <= 0) {
      return 0;
    }

    return ((xpTotal - currentLevelXp) / levelRange).clamp(0.0, 1.0).toDouble();
  }
}
