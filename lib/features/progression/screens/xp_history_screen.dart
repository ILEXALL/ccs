import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/firestore/collections.dart'
    show xpTransactionsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'package:ccs_app/features/progression/data/xp_access.dart'
    show canReadXpStatsForUser;
import 'package:ccs_app/features/progression/models/xp_transaction.dart'
    show XpTransactionData;
import 'package:ccs_app/features/progression/widgets/xp_transaction_tile.dart'
    show XpTransactionTile;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class XpHistoryScreen extends StatelessWidget {
  final String userId;

  const XpHistoryScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final cleanUserId = userId.trim();

    if (cleanUserId != currentUser.uid)
      return PublicXpHistoryScreen(userId: cleanUserId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('XP History'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: !canReadXpStatsForUser(cleanUserId)
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyStateCard(
                icon: Icons.lock_outline,
                title: 'Could not load XP history.',
                text: 'XP is being calculated',
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: xpTransactionsCollection()
                  .where('userId', isEqualTo: cleanUserId)
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .debugSnapshots('profile: xp history listener'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyStateCard(
                      icon: Icons.warning_amber_rounded,
                      title: 'Could not load XP history.',
                      text: 'XP is being calculated',
                    ),
                  );
                }

                final transactions =
                    snapshot.data?.docs
                        .map(XpTransactionData.fromFirestore)
                        .toList() ??
                    <XpTransactionData>[];
                transactions.sort(
                  (first, second) =>
                      second.createdAtMillis.compareTo(first.createdAtMillis),
                );

                if (transactions.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: const [
                      EmptyStateCard(
                        icon: Icons.history,
                        title: 'No XP history yet',
                        text:
                            'Earn XP by completing your profile, garage, or approved spots.',
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    const CcsText(
                      'Recent XP activity',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final transaction in transactions)
                      XpTransactionTile(transaction: transaction),
                  ],
                );
              },
            ),
    );
  }
}

class PublicXpHistoryScreen extends StatefulWidget {
  final String userId;
  const PublicXpHistoryScreen({super.key, required this.userId});
  @override
  State<PublicXpHistoryScreen> createState() => _PublicXpHistoryScreenState();
}

class _PublicXpHistoryScreenState extends State<PublicXpHistoryScreen> {
  late Future<Map<String, dynamic>> request;
  void load() {
    request = xpScreenRequest('public_xp', {
      'userId': widget.userId,
      'section': 'history',
    });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PublicXpHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const CcsText('XP History'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: trText('Retry'),
          onPressed: () => setState(load),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CcsText('Could not load XP history.'),
                TextButton(
                  onPressed: () => setState(load),
                  child: CcsText(
                    achievementText(
                      appUiPreferences.language.name,
                      'Retry',
                      'Повторить',
                      'Mēģināt vēlreiz',
                    ),
                  ),
                ),
              ],
            ),
          );
        final items = (snapshot.data?['items'] as List? ?? []).cast<Map>();
        if (items.isEmpty) {
          return const Center(child: CcsText('No XP history yet'));
        }
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            for (final item in items)
              XpTransactionTile(
                transaction: XpTransactionData(
                  id: '',
                  userId: widget.userId,
                  action: item['action'] as String,
                  objectType: item['objectType'] as String,
                  objectId: item['achievementId'] as String? ?? '',
                  stage: '',
                  status: 'confirmed',
                  reason: '',
                  weekKey: '',
                  amount: intFromFirebase(item['amount'], 0),
                  requestedAmount: 0,
                  createdAtMillis: intFromFirebase(item['createdAtMillis'], 0),
                  metadata: const {},
                ),
              ),
          ],
        );
      },
    ),
  );
}
