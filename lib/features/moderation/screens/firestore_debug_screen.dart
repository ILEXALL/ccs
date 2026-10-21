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
        final operationTotal = entries.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (_sortBy == 'Writes'
                  ? entry.value.writes
                  : _sortBy == 'Deletes'
                  ? entry.value.deletes
                  : entry.value.reads),
        );
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
                'Read sources on this device',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const CcsText(
                'Estimated activity from this device only, highest first. These figures do not break down the project-wide cloud total.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
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
                ...entries.indexed.map((ranked) {
                  final (index, entry) = ranked;
                  final count = _sortBy == 'Writes'
                      ? entry.value.writes
                      : _sortBy == 'Deletes'
                      ? entry.value.deletes
                      : entry.value.reads;
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
                          '${index + 1}. ${entry.key}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ReadShareBar(
                          count: count,
                          total: operationTotal,
                          estimated: true,
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
    final readSources =
        snapshot == null
              ? <({String title, String description, int count})>[]
              : [
                  (
                    title: 'Query reads',
                    description:
                        'Documents read by queries, such as lists and filtered results.',
                    count: snapshot.queryReads,
                  ),
                  (
                    title: 'Document lookups',
                    description: 'Documents fetched directly by their IDs.',
                    count: snapshot.lookupReads,
                  ),
                  if (snapshot.reads >
                      snapshot.queryReads + snapshot.lookupReads)
                    (
                      title: 'Other / not attributed',
                      description:
                          'Reads not covered by the reported query and lookup totals.',
                      count:
                          snapshot.reads -
                          snapshot.queryReads -
                          snapshot.lookupReads,
                    ),
                ]
          ..sort((a, b) => b.count.compareTo(a.count));
    final breakdownTotal = readSources.fold<int>(
      0,
      (sum, row) => sum + row.count,
    );
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
            'Project-wide • all users and backend • UTC. Google metrics can arrive several minutes late; these are operation counts, not a final invoice.',
            style: TextStyle(color: Colors.white60, height: 1.4, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const {
                'day': 'Today',
                'week': 'This week',
                'month': 'This month',
              }.entries)
                ChoiceChip(
                  label: CcsText(option.value),
                  selected: controller.selectedPeriod == option.key,
                  onSelected: controller.isLoading
                      ? null
                      : (_) => unawaited(controller.selectPeriod(option.key)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          CcsText(switch (controller.selectedPeriod) {
            'week' => 'Monday 00:00 UTC to now',
            'month' => '1st of this month, 00:00 UTC to now',
            _ => 'Today 00:00 UTC to now',
          }, style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: blue.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CcsText(
                    'Estimated charges so far this month:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  CcsText(
                    snapshot.monthlyEstimateEur == null
                        ? 'Estimate unavailable'
                        : '€${snapshot.monthlyEstimateEur!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const CcsText(
                    'Document operations so far this month, after daily free allowances. Excludes storage, network traffic, backups, other charges and taxes. Not the full invoice or a month-end forecast.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (snapshot.pricingChecked != null)
                    CcsText(
                      'EUR prices checked: ${snapshot.pricingChecked}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
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
            const CcsText(
              'What causes reads',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const CcsText(
              'Ranked by measured read volume, highest first — not a monetary cost estimate. Google does not attribute these totals to app screens or collections.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            for (final ranked in readSources.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      '${ranked.$1 + 1}. ${ranked.$2.title}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      ranked.$2.description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ReadShareBar(
                      count: ranked.$2.count,
                      total: breakdownTotal,
                    ),
                  ],
                ),
              ),
            if (snapshot.reads < snapshot.queryReads + snapshot.lookupReads)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CcsText(
                  'The total and breakdown were sampled separately and may differ while metrics update.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            CcsText(
              'Recent 10 minutes • connections: ${snapshot.activeConnections} • listeners: ${snapshot.snapshotListeners}',
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

class _ReadShareBar extends StatelessWidget {
  const _ReadShareBar({
    required this.count,
    required this.total,
    this.estimated = false,
  });
  final int count;
  final int total;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final share = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CcsText(
          '${estimated ? '~' : ''}$count • ${(share * 100).toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 5,
            color: blue,
            backgroundColor: Colors.white10,
          ),
        ),
      ],
    );
  }
}
