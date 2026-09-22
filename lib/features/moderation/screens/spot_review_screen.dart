import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/moderation/data/spot_review_lease.dart'
    show SpotReviewLease;
import 'package:ccs_app/features/moderation/screens/admin_edit_spot_screen.dart'
    show openAdminEditSpot;
import 'package:ccs_app/features/moderation/widgets/admin_status_badge.dart'
    show AdminStatusBadge;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show deleteAdminSpot, showAdminActionError;
import 'package:ccs_app/features/spots/data/spot_mutations.dart'
    show updateSpotStatus;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;

class AdminSpotReviewScreen extends StatefulWidget {
  final CarSpot spot;
  const AdminSpotReviewScreen({super.key, required this.spot});
  @override
  State<AdminSpotReviewScreen> createState() => _AdminSpotReviewScreenState();
}

class _AdminSpotReviewScreenState extends State<AdminSpotReviewScreen>
    with WidgetsBindingObserver, LanguageReactiveState {
  late final SpotReviewLease _lease;
  CarSpot? _spot;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _lease = SpotReviewLease(widget.spot.id);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _spot = null;
    });
    try {
      if (await _lease.acquire()) {
        final doc = await spotsCollection()
            .doc(widget.spot.id)
            .debugGet(
              const GetOptions(source: Source.server),
              'review: locked spot',
            )
            .timeout(const Duration(seconds: 15));
        if (!doc.exists) throw StateError('Spot is no longer available');
        if (mounted && _lease.active) _spot = CarSpot.fromFirestore(doc);
      }
    } catch (error, stack) {
      debugPrint(
        'Spot review opening failed (${widget.spot.id}): $error\n$stack',
      );
      _lease.markLost(error: error, opening: true);
      unawaited(_lease.release());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    await _lease.runAction(() async {
      try {
        await _lease.ensureActive();
        if (!mounted) return;
        await openAdminEditSpot(context, _spot!, reviewLease: _lease);
        if (!mounted || !_lease.active) return;
        final doc = await spotsCollection()
            .doc(widget.spot.id)
            .debugGet(
              const GetOptions(source: Source.server),
              'review: after editing',
            )
            .timeout(const Duration(seconds: 15));
        if (!doc.exists) throw StateError('Spot is no longer available');
        if (mounted) setState(() => _spot = CarSpot.fromFirestore(doc));
      } catch (error, stack) {
        debugPrint('Spot review editing failed: $error\n$stack');
        _lease.markLost(error: error);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _lease.suspend();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_lease.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lease,
    builder: (context, _) {
      final ready = !_loading && _spot != null && _lease.active;
      return PopScope(
        canPop: !_lease.busy,
        child: ready
            ? AbsorbPointer(
                absorbing: _lease.busy,
                child: _LockedAdminSpotReviewScreen(
                  spot: _spot!,
                  lease: _lease,
                  onEdit: () => unawaited(_edit()),
                ),
              )
            : Scaffold(
                appBar: AppBar(title: CcsText(trText('Manage Spot'))),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 40),
                              const SizedBox(height: 16),
                              CcsText(
                                _lease.reviewerUsername.isNotEmpty
                                    ? '${trText('Currently being reviewed by')} @${_lease.reviewerUsername}'
                                    : trText(
                                        _lease.errorText.isEmpty
                                            ? 'Another reviewer has this spot open.'
                                            : _lease.errorText,
                                      ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _load,
                                child: CcsText(trText('Try again')),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
      );
    },
  );
}

class _LockedAdminSpotReviewScreen extends StatelessWidget {
  final CarSpot spot;
  final SpotReviewLease lease;
  final VoidCallback onEdit;
  const _LockedAdminSpotReviewScreen({
    required this.spot,
    required this.lease,
    required this.onEdit,
  });

  Future<void> approveSpot(BuildContext context) async {
    try {
      await lease.ensureActive();
      await updateSpotStatus(
        spot,
        SpotStatus.approved,
        reviewSessionId: lease.sessionId,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Spot approved. It is now public.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not approve spot',
        error: error,
      );
    }
  }

  Future<String?> askRejectionReason(BuildContext context) async {
    final controller = TextEditingController();

    return await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const CcsText(
            'Reject spot?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterStyle: const TextStyle(color: Colors.white38),
              hintText: 'Write the reason the user will see...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const CcsText('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: CcsText(
                        'Write a rejection reason first.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, reason);
              },
              icon: const Icon(Icons.close),
              label: const CcsText('Reject'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> rejectSpot(BuildContext context) async {
    final reason = await askRejectionReason(context);
    if (reason == null || reason.trim().isEmpty) {
      return;
    }

    try {
      await updateSpotStatus(
        spot,
        SpotStatus.rejected,
        reviewSessionId: lease.sessionId,
        rejectionReason: reason,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Spot rejected and reason sent to the user.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not reject spot',
        error: error,
      );
    }
  }

  Future<void> deleteSpot(BuildContext context) async {
    await deleteAdminSpot(context, spot, popAfterDelete: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!currentUserCanModerateSpot(spot)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: CcsText(trText('Manage Spot')),
          backgroundColor: Colors.transparent,
          foregroundColor: blue,
        ),
        body: Center(
          child: CcsText(
            trText('This spot is outside your assigned countries'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Manage Spot'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          SpotPhoto(
            spot: spot,
            height: 250,
            width: double.infinity,
            borderRadius: BorderRadius.circular(22),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              AdminStatusBadge(status: spot.status),
              const Spacer(),
              Flexible(
                child: spot.addedByUid.trim().isEmpty
                    ? CcsText(
                        'Added by ${spot.addedBy}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54),
                      )
                    : InkWell(
                        onTap: () => openUserProfile(
                          context,
                          uid: spot.addedByUid,
                          fallbackUsername: spot.addedBy,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        child: CcsText(
                          'Added by ${displayUsername(spot.addedBy)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CcsText(
            spot.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          CcsText(
            spot.cityCountry,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          CcsText(
            spot.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          if (spot.status == SpotStatus.rejected &&
              spot.rejectionReason.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.redAccent),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CcsText(
                          'Rejection reason',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        CcsText(
                          spot.rejectionReason,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (spot.verifiedOnly)
                SpotInfoTag(label: 'Verified only', icon: Icons.verified_user),
              for (final category in spot.categories)
                SpotInfoTag(label: category, icon: Icons.local_offer),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: CcsText(trText('Edit all spot information')),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue.withValues(alpha: 0.18),
                foregroundColor: blue,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (spot.status == SpotStatus.approved)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  unawaited(lease.runAction(() => deleteSpot(context)));
                },
                icon: const Icon(Icons.delete_outline),
                label: const CcsText('Remove'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      unawaited(lease.runAction(() => rejectSpot(context)));
                    },
                    icon: const Icon(Icons.close),
                    label: const CcsText('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      unawaited(lease.runAction(() => approveSpot(context)));
                    },
                    icon: const Icon(Icons.check),
                    label: const CcsText('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
