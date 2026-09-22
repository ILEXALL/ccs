import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugStats, firestoreDebugTracker;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/cloud_usage.dart'
    show FirestoreCloudUsageController, firestoreCloudUsageController;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/utils/date_formatting.dart' show twoDigits;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class FirestoreDebugScreen extends StatefulWidget {
  const FirestoreDebugScreen({super.key});

  @override
  State<FirestoreDebugScreen> createState() => _FirestoreDebugScreenState();
}

class _FirestoreDebugScreenState extends State<FirestoreDebugScreen> {
  Timer? _cloudUsageRefreshTimer;
  String _sortBy = 'Reads';

  @override
  void initState() {
    super.initState();
    if (currentUser.role != UserRole.admin) return;
    unawaited(firestoreCloudUsageController.loadBaseline());
    unawaited(firestoreCloudUsageController.refresh());
    _cloudUsageRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(firestoreCloudUsageController.refresh());
    });
  }

  @override
  void dispose() {
    _cloudUsageRefreshTimer?.cancel();
    super.dispose();
  }

  String _timeLabel(DateTime? value) {
    if (value == null) {
      return '-';
    }

    return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  Future<void> _resetCounters() async {
    if (currentUser.role != UserRole.admin) return;
    firestoreDebugTracker.reset();
    // Reset only this device's diagnostic window; cloud totals stay unchanged.
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser.role != UserRole.admin) {
      return const Scaffold(body: Center(child: CcsText('No access')));
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        firestoreDebugTracker,
        firestoreCloudUsageController,
      ]),
      builder: (context, _) {
        final entries =
            firestoreDebugTracker.sessionStatsByLabel.entries.toList()
              ..sort((first, second) {
                int value(FirestoreDebugStats stats) => _sortBy == 'Writes'
                    ? stats.writes
                    : _sortBy == 'Deletes'
                    ? stats.deletes
                    : stats.reads;
                final readCompare = value(
                  second.value,
                ).compareTo(value(first.value));
                if (readCompare != 0) {
                  return readCompare;
                }
                return second.value.total.compareTo(first.value.total);
              });
        final logs = firestoreDebugTracker.recentEvents;
        final unlabeledEvents = firestoreDebugTracker.unlabeledEvents;
        final hasUnlabeledCalls = unlabeledEvents > 0;
        final sessionStartedLabel = _timeLabel(
          firestoreDebugTracker.sessionStartedAt,
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const CcsText('Firestore usage'),
            backgroundColor: Colors.transparent,
            foregroundColor: blue,
            actions: [
              IconButton(
                tooltip: 'Refresh Firebase usage',
                onPressed: firestoreCloudUsageController.isLoading
                    ? null
                    : () => unawaited(firestoreCloudUsageController.refresh()),
                icon: const Icon(Icons.cloud_sync_outlined),
              ),
              IconButton(
                tooltip: 'Start a new device measurement',
                onPressed: () => unawaited(_resetCounters()),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _FirestoreCloudUsageCard(
                controller: firestoreCloudUsageController,
                timeLabel: _timeLabel,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panelGlass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      'This device • server activity estimate • since $sessionStartedLabel',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _FirestoreDebugTotal(
                            label: 'Reads',
                            value: firestoreDebugTracker.sessionReads,
                            icon: Icons.download_outlined,
                          ),
                        ),
                        Expanded(
                          child: _FirestoreDebugTotal(
                            label: 'Writes',
                            value: firestoreDebugTracker.sessionWrites,
                            icon: Icons.upload_outlined,
                          ),
                        ),
                        Expanded(
                          child: _FirestoreDebugTotal(
                            label: 'Deletes',
                            value: firestoreDebugTracker.sessionDeletes,
                            icon: Icons.delete_outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const CcsText(
                      'Cache snapshots and pending or failed writes are excluded. Reads are estimates, not billing totals: shared listeners, reconnects, query removals, index reads and security-rule reads cannot be measured exactly by the app. Backend and other-device activity appears only in the cloud totals.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: hasUnlabeledCalls
                      ? Colors.orangeAccent.withValues(alpha: 0.12)
                      : panelGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasUnlabeledCalls
                        ? Colors.orangeAccent
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      hasUnlabeledCalls
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined,
                      color: hasUnlabeledCalls ? Colors.orangeAccent : blue,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CcsText(
                        hasUnlabeledCalls
                            ? 'Tracking audit: $unlabeledEvents unlabeled Firestore events need manual labels. Look for rows starting with UNLABELED.'
                            : 'Tracking audit: all Firestore calls that reached the tracker have manual labels. Raw SDK calls outside debug wrappers still need source search.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const CcsText(
                'Feature costs on this device',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _sortBy,
                dropdownColor: panel,
                items: ['Reads', 'Writes', 'Deletes']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: CcsText('Sort by $value'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _sortBy = value);
                },
              ),
              if (entries.isEmpty)
                const EmptyStateCard(
                  icon: Icons.bug_report_outlined,
                  title: 'No Firestore calls tracked yet',
                  text: 'Use the app for a minute, then return here.',
                )
              else
                ...entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CcsText(
                          entry.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        CcsText(
                          'Reads ~${entry.value.reads}  •  Writes ${entry.value.writes}  •  Deletes ${entry.value.deletes}  •  last ${_timeLabel(entry.value.lastAt)}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 14),
              const CcsText(
                'Recent events',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                const CcsText(
                  'No recent events yet.',
                  style: TextStyle(color: Colors.white54),
                )
              else
                ...logs.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: CcsText(
                      '${_timeLabel(entry.at)}  ${entry.operation}  ${entry.count}  ${entry.label}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _FirestoreCloudUsageCard extends StatelessWidget {
  final FirestoreCloudUsageController controller;
  final String Function(DateTime?) timeLabel;
  const _FirestoreCloudUsageCard({
    required this.controller,
    required this.timeLabel,
  });
  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final error = controller.errorMessage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined, color: blue),
              const SizedBox(width: 8),
              const Expanded(
                child: CcsText(
                  'Actual Firestore activity',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (controller.isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const CcsText(
            'Project-wide • all users and backend • today (UTC). Google metrics can arrive several minutes late; these are operation counts, not a final invoice.',
            style: TextStyle(color: Colors.white60, height: 1.4, fontSize: 12),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            CcsText(
              snapshot == null
                  ? 'Cloud usage unavailable. No usage total is shown.'
                  : 'Refresh failed. Showing the last successful report.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            CcsText(
              error,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          if (snapshot == null && error == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: CcsText(
                'Waiting for Google Cloud metrics…',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          if (snapshot != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _FirestoreDebugTotal(
                    label: 'Reads',
                    value: snapshot.reads,
                    icon: Icons.download_outlined,
                  ),
                ),
                Expanded(
                  child: _FirestoreDebugTotal(
                    label: 'Writes',
                    value: snapshot.writes,
                    icon: Icons.upload_outlined,
                  ),
                ),
                Expanded(
                  child: _FirestoreDebugTotal(
                    label: 'Deletes',
                    value: snapshot.deletes,
                    icon: Icons.delete_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CcsText(
              'Read breakdown: query ${snapshot.queryReads} • lookup ${snapshot.lookupReads}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            CcsText(
              'Connections: ${snapshot.activeConnections} • listeners: ${snapshot.snapshotListeners}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            CcsText(
              'Last refresh: ${timeLabel(controller.lastFetchedAt)}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _FirestoreDebugTotal extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _FirestoreDebugTotal({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: blue, size: 20),
        const SizedBox(height: 6),
        CcsText(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        CcsText(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
