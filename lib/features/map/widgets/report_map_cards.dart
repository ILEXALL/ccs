import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/features/map/models/sos_report.dart'
    show SosReportData, sosReasonLabel;
import 'package:ccs_app/features/map/widgets/map_profile_actions.dart'
    show MapPreviewProfileActions;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;

class SosReportMapCard extends StatelessWidget {
  final SosReportData report;
  final bool isOwnReport;
  final VoidCallback onOpenProfile;
  final VoidCallback onMessage;
  final VoidCallback onRoute;
  final VoidCallback? onDelete;

  const SosReportMapCard({
    super.key,
    required this.report,
    this.isOwnReport = false,
    required this.onOpenProfile,
    required this.onMessage,
    required this.onRoute,
    this.onDelete,
  });

  String get timeLeftLabel {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      report.expiresAtMillis,
    );
    final left = expiresAt.difference(DateTime.now());

    if (left.isNegative) {
      return 'expired';
    }

    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m left';
    }

    return '${left.inMinutes.clamp(0, 720)}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: blue.withValues(alpha: 0.42)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: CcsText(
                    'SOS',
                    style: TextStyle(
                      color: blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CcsText(
                      'Help request',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: isOwnReport ? null : onOpenProfile,
                      child: CcsText(
                        isOwnReport
                            ? 'Your SOS - $timeLeftLabel'
                            : '@${displayUsername(report.username)} - $timeLeftLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOwnReport ? Colors.white54 : blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: blue.withValues(alpha: 0.26)),
            ),
            child: CcsText(
              trText(sosReasonLabel(report.reason)),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          CcsText(
            report.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
          if (!isOwnReport) ...[
            const SizedBox(height: 12),
            MapPreviewProfileActions(
              onOpen: onOpenProfile,
              onSecondary: onMessage,
              secondaryLabel: 'Write message',
              secondaryIcon: Icons.chat_bubble_outline,
              filledSecondary: false,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRoute,
                icon: const Icon(Icons.route, size: 18),
                label: const CcsText('Open Waze'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            if (onDelete != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: CcsText(trText('Delete SOS')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: blue,
                    side: const BorderSide(color: blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            CcsText(
              trText('Other drivers can see this SOS and contact you.'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PoliceReportMapCard extends StatelessWidget {
  final PoliceReportData report;
  final bool isBusy;
  final bool canVote;
  final String voteHint;
  final VoidCallback onStillThere;
  final VoidCallback onNotThere;
  final VoidCallback? onDelete;

  const PoliceReportMapCard({
    super.key,
    required this.report,
    required this.isBusy,
    required this.canVote,
    required this.voteHint,
    required this.onStillThere,
    required this.onNotThere,
    this.onDelete,
  });

  String get timeLeftLabel {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      report.expiresAtMillis,
    );
    final left = expiresAt.difference(DateTime.now());

    if (left.isNegative) {
      return 'expired';
    }

    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m left';
    }

    return '${left.inMinutes.clamp(0, 120)}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_police, color: Colors.redAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CcsText(
                      'Police nearby',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: report.uid.trim().isEmpty
                          ? null
                          : () => openUserProfile(
                              context,
                              uid: report.uid,
                              fallbackUsername: report.username,
                            ),
                      borderRadius: BorderRadius.circular(999),
                      child: CcsText(
                        'Marked by ${displayUsername(report.username)} - $timeLeftLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SpotInfoTag(
                label: '${report.stillThereCount} still there',
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              SpotInfoTag(
                label: '${report.notThereCount} not there',
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (onDelete != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: CcsText(trText('Delete police mark')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!canVote)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: CcsText(
                voteHint.isEmpty
                    ? 'You can confirm this mark when you are close to it.'
                    : voteHint,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onNotThere,
                    icon: const Icon(Icons.close, size: 18),
                    label: const CcsText('Not there'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : onStillThere,
                    icon: const Icon(Icons.check, size: 18),
                    label: const CcsText('Still there'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
