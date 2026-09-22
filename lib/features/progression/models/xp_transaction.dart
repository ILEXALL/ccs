import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        intFromFirebase,
        mapFromFirebase,
        stringFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show formatXpValue;
import 'package:ccs_app/features/progression/widgets/xp_labels.dart'
    show
        xpTransactionActionLabel,
        xpTransactionObjectTypeLabel,
        xpTransactionReasonLabel,
        xpTransactionStatusLabel;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

class XpTransactionData {
  final String id;
  final String userId;
  final String action;
  final String objectType;
  final String objectId;
  final String stage;
  final String status;
  final String reason;
  final String weekKey;
  final int amount;
  final int requestedAmount;
  final int createdAtMillis;
  final Map<String, dynamic> metadata;

  const XpTransactionData({
    required this.id,
    required this.userId,
    required this.action,
    required this.objectType,
    required this.objectId,
    required this.stage,
    required this.status,
    required this.reason,
    required this.weekKey,
    required this.amount,
    required this.requestedAmount,
    required this.createdAtMillis,
    required this.metadata,
  });

  factory XpTransactionData.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = timestampMillisFromFirebase(data['createdAt']);

    return XpTransactionData(
      id: stringFromFirebase(data['transactionId'], doc.id),
      userId: stringFromFirebase(data['userId'], ''),
      action: stringFromFirebase(data['action'], ''),
      objectType: stringFromFirebase(data['objectType'], ''),
      objectId: stringFromFirebase(data['objectId'], ''),
      stage: stringFromFirebase(data['stage'], ''),
      status: stringFromFirebase(data['status'], 'pending').toLowerCase(),
      reason: stringFromFirebase(data['reason'], ''),
      weekKey: stringFromFirebase(data['weekKey'], ''),
      amount: intFromFirebase(data['amount'], 0),
      requestedAmount: intFromFirebase(data['requestedAmount'], 0),
      createdAtMillis: createdAt > 0
          ? createdAt
          : intFromFirebase(data['createdAtMillis'], 0),
      metadata: mapFromFirebase(data['metadata']),
    );
  }

  bool get isPositive => status == 'confirmed' && amount > 0;

  String get title {
    if (['weekly.completed', 'admin_reward.completed'].contains(action) &&
        metadata['title'] is Map) {
      final titles = metadata['title'] as Map;
      return titles[appUiPreferences.language.name] as String? ??
          titles['en'] as String? ??
          xpTransactionActionLabel(action);
    }
    if (action == 'achievement.unlock') {
      final parts = objectId.split('.');
      if (parts.length == 2) {
        final requirement = achievementRequirement({
          'category': parts.first,
          'threshold': parts.last,
        }, appUiPreferences.language.name);
        return '${xpTransactionActionLabel(action)}: $requirement${parts.first == 'tourist' ? ' (${parts.last})' : ''}';
      }
    }
    return xpTransactionActionLabel(action);
  }

  String get category => xpTransactionObjectTypeLabel(objectType);

  String get statusLabel => xpTransactionStatusLabel(status);

  String get reasonLabel => xpTransactionReasonLabel(reason);

  String get createdAtLabel {
    if (createdAtMillis <= 0) {
      return '';
    }

    return formatShortDateTime(
      DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }

  String get amountLabel {
    if (amount > 0) {
      return '+${formatXpValue(amount)} XP';
    }

    if (amount < 0) {
      return '-${formatXpValue(amount.abs())} XP';
    }

    return '0 XP';
  }
}
