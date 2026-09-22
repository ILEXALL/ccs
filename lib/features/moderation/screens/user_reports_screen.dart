import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show userReportsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/moderation/data/user_reports.dart'
    show regionalUserReportsStream;
import 'package:ccs_app/features/moderation/models/user_report.dart'
    show UserReportData;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show showAdminActionError;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;
import 'package:ccs_app/shared/utils/date_formatting.dart' show twoDigits;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class AdminUserReportsScreen extends StatelessWidget {
  const AdminUserReportsScreen({super.key});

  String reportTimeLabel(int millis) {
    if (millis <= 0) {
      return trText('Just now');
    }

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  Future<void> updateReportStatus(
    BuildContext context,
    UserReportData report,
    String status,
  ) async {
    try {
      await userReportsCollection()
          .doc(report.id)
          .debugSet(
            {
              'status': status,
              'reviewedByUid': currentUser.uid,
              'reviewedBy': currentUser.username,
              'reviewedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
            'admin: update user report status',
          );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            trText(
              status == 'resolved' ? 'Report resolved.' : 'Report reviewed.',
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } catch (error) {
      showAdminActionError(
        context,
        message: trText('Could not update report'),
        error: error,
      );
    }
  }

  Widget reportTile(BuildContext context, UserReportData report) {
    final statusColor = report.isOpen ? Colors.orangeAccent : blue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.report_outlined, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CcsText(
                            displayUsername(report.reportedUsername),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        UserPrimaryBadge(
                          role: report.reportedRole,
                          verified: userRoleIsStaff(report.reportedRole),
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    CcsText(
                      '${trText('Reported by')} ${displayUsername(report.reporterUsername)} • ${reportTimeLabel(report.createdAtMillis)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    CcsText(
                      trText(report.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CcsText(
            report.reason.isEmpty
                ? trText('No reason provided.')
                : report.reason,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: report.reportedUid.trim().isEmpty
                    ? null
                    : () => openUserProfile(
                        context,
                        uid: report.reportedUid,
                        fallbackUsername: report.reportedUsername,
                      ),
                icon: const Icon(Icons.person_outline),
                label: CcsText(trText('Open reported profile')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: blue,
                  side: BorderSide(color: blue.withValues(alpha: 0.7)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: report.reporterUid.trim().isEmpty
                    ? null
                    : () => openUserProfile(
                        context,
                        uid: report.reporterUid,
                        fallbackUsername: report.reporterUsername,
                      ),
                icon: const Icon(Icons.visibility_outlined),
                label: CcsText(trText('Open reporter')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              if (report.status != 'reviewed')
                ElevatedButton.icon(
                  onPressed: () => unawaited(
                    updateReportStatus(context, report, 'reviewed'),
                  ),
                  icon: const Icon(Icons.done_all),
                  label: CcsText(trText('Mark reviewed')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (report.status != 'resolved')
                ElevatedButton.icon(
                  onPressed: () => unawaited(
                    updateReportStatus(context, report, 'resolved'),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: CcsText(trText('Resolve')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText('User reports')),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: regionalUserReportsStream(),
        builder: (context, snapshot) {
          final reports =
              snapshot.data
                  ?.map((doc) => UserReportData.fromFirestore(doc))
                  .toList() ??
              const <UserReportData>[];
          final openCount = reports.where((report) => report.isOpen).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              CcsText(
                trText('User reports'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              CcsText(
                reports.isEmpty
                    ? trText('No user reports yet.')
                    : '$openCount open • ${reports.length} total',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (reports.isEmpty)
                const EmptyStateCard(
                  icon: Icons.report_outlined,
                  title: 'No user reports yet',
                  text:
                      'Reports submitted from public profiles will appear here.',
                )
              else
                for (final report in reports) ...[
                  reportTile(context, report),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}
