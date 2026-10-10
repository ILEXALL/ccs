import 'package:ccs_app/features/events/widgets/event_editorial_actions.dart';
import 'package:ccs_app/features/events/widgets/event_detail_overview.dart';
import 'package:ccs_app/features/spots/widgets/spot_detail_header.dart'
    show SpotDetailCompactHeader;
import 'package:ccs_app/features/spots/widgets/spot_detail_header.dart'
    show SpotDetailMetaRow;
import 'package:ccs_app/features/spots/widgets/spot_business_details.dart'
    show SpotBusinessStatusCard;
import 'package:ccs_app/features/spots/widgets/spot_business_details.dart'
    show SpotContactSection;
import 'package:ccs_app/features/spots/widgets/spot_detail_actions.dart'
    show SpotDetailEngagementPanel;
import 'package:ccs_app/features/spots/widgets/spot_detail_actions.dart'
    show SpotRouteActions;
import 'package:ccs_app/features/spots/controllers/spot_detail_view_state.dart';
import 'package:ccs_app/features/spots/controllers/spot_detail_controller.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot, memberSpotGroups;
import 'package:ccs_app/features/spots/widgets/save_spot_button.dart'
    show SaveSpotButton;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanManageSpotBusiness, currentUserCanModerateSpot;
import 'package:ccs_app/features/moderation/screens/admin_edit_spot_screen.dart'
    show AdminEditSpotScreen;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show deleteAdminSpot;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show canTransferSpotOwnership;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/edit_business_screen.dart'
    show ServiceSpotBusinessEditScreen;
import 'package:ccs_app/features/spots/screens/ownership_transfer_dialog.dart'
    show showSpotOwnershipTransfer;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;
import 'package:ccs_app/features/spots/widgets/spot_reviews_section.dart'
    show SpotReviewsSection;
import 'package:ccs_app/shared/media/photo_gallery.dart' show SpotPhotoCarousel;
import 'package:ccs_app/shared/models/user_role.dart'
    show userRoleIsAdmin, userRoleIsModerator;

class SpotDetailScreen extends StatefulWidget implements SpotDetailInputs {
  @override
  final CarSpot spot;

  // Optional stream keeps detail reconciliation independently testable.
  @override
  final Stream<CarSpot?>? spotUpdates;

  const SpotDetailScreen({super.key, required this.spot, this.spotUpdates});

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen>
    with LanguageReactiveState
    implements SpotDetailViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  late final SpotDetailControllerActions controller = SpotDetailController(
    this,
  );

  @override
  late CarSpot spot;
  @override
  StreamSubscription<CarSpot?>? spotSubscription;
  @override
  bool spotUnavailable = false;

  @override
  void initState() {
    super.initState();
    spot = widget.spot;
    final updates =
        widget.spotUpdates ??
        (spot.id.isEmpty
            ? null
            : spotsCollection()
                  .doc(spot.id)
                  .snapshots(includeMetadataChanges: true)
                  // A cache miss is not proof that the server deleted the spot.
                  .where(
                    (snapshot) =>
                        snapshot.exists || !snapshot.metadata.isFromCache,
                  )
                  .map(
                    (snapshot) => snapshot.exists
                        ? CarSpot.fromFirestore(snapshot)
                        : null,
                  ));
    spotSubscription = updates?.listen(
      (current) {
        if (!mounted) return;
        setState(() {
          spotUnavailable = current == null;
          if (current != null) spot = current;
        });
      },
      onError: (Object error) {
        if (mounted &&
            error is FirebaseException &&
            (error.code == 'permission-denied' || error.code == 'not-found')) {
          setState(() => spotUnavailable = true);
        }
      },
    );
    memberSpotGroups.addListener(controller.groupAccessChanged);
  }

  @override
  void dispose() {
    memberSpotGroups.removeListener(controller.groupAccessChanged);
    spotSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (spotUnavailable) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: CcsText(trText('This spot is no longer available.')),
        ),
      );
    }
    if (!canViewGroupSpot(spot))
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: CcsText(
            trText('This spot is available only to members of its groups.'),
          ),
        ),
      );
    return Scaffold(
      backgroundColor: spot.isTemporary
          ? const Color(0xFF0C111A)
          : Colors.transparent,
      appBar: AppBar(
        title: CcsText(
          spot.isTemporary
              ? communityText(en: 'Event', ru: 'Событие', lv: 'Pasākums')
              : 'Spot',
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Center(child: SaveSpotButton(spot: spot, compact: true)),
          ),
          if (canTransferSpotOwnership(
            currentUser,
            countryCode: spot.countryCode,
          ))
            IconButton(
              tooltip: communityText(
                en: 'Transfer ownership',
                ru: 'Передать владение',
                lv: 'Nodot īpašumtiesības',
              ),
              icon: const Icon(Icons.manage_accounts_outlined),
              onPressed: () async {
                final updated = await showSpotOwnershipTransfer(context, spot);
                if (updated != null && mounted) setState(() => spot = updated);
              },
            ),
          if (currentUserCanModerateSpot(spot) ||
              spot.addedByUid == currentUser.uid)
            IconButton(
              tooltip: trText('Edit spot'),
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  appPageRoute(builder: (_) => AdminEditSpotScreen(spot: spot)),
                );
                if (saved == true && mounted) {
                  final fresh = await spotsCollection().doc(spot.id).debugGet();
                  if (fresh.exists && mounted) {
                    setState(() => spot = CarSpot.fromFirestore(fresh));
                  }
                }
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          if (userRoleIsAdmin(currentUser.role) ||
              (userRoleIsModerator(currentUser.role) &&
                  currentUserCanModerateSpot(spot)))
            IconButton(
              tooltip: userRoleIsAdmin(currentUser.role)
                  ? 'Delete spot'
                  : 'Request spot removal',
              onPressed: () async {
                await deleteAdminSpot(
                  context,
                  spot,
                  popAfterDelete: userRoleIsAdmin(currentUser.role),
                );
              },
              icon: Icon(
                userRoleIsAdmin(currentUser.role)
                    ? Icons.delete_outline
                    : Icons.delete_sweep_outlined,
                color: Colors.redAccent,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          SpotPhotoCarousel(
            spot: spot,
            containWithBlur: spot.isTemporary,
            height: math.min(
              MediaQuery.of(context).size.width *
                  (spot.isTemporary ? 0.62 : 0.82),
              spot.isTemporary ? 300 : 340,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (spot.isTemporary)
                  EventDetailOverview(
                    spot: spot,
                    onShowMap: controller.showSpotOnMap,
                  )
                else
                  SpotDetailCompactHeader(spot: spot),
                if (spot.isTemporary) ...[
                  EventEditorialActions(spot: spot),
                  const Divider(height: 1, color: Color(0xFF263647)),
                ] else ...[
                  const SizedBox(height: 8),
                  SpotDetailEngagementPanel(spot: spot),
                  const SizedBox(height: 8),
                  SpotDetailMetaRow(spot: spot),
                  const SizedBox(height: 8),
                  SpotRouteActions(
                    spot: spot,
                    onShowMap: controller.showSpotOnMap,
                  ),
                ],
                if (spot.isTemporary) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final category in spot.categories)
                        CcsText(
                          trText(category),
                          style: const TextStyle(
                            color: Color(0xFF8FC8FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
                if (spot.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  CcsText(
                    spot.description,
                    softWrap: true,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (!spot.isTemporary)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in spot.categories)
                        SpotInfoTag(label: category, icon: Icons.local_offer),
                    ],
                  ),
                if (spot.supportsContacts) ...[
                  const SizedBox(height: 16),
                  SpotBusinessStatusCard(spot: spot),
                ],
                if (currentUserCanManageSpotBusiness(spot)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final updatedSpot = await Navigator.push<CarSpot>(
                          context,
                          appPageRoute(
                            builder: (_) =>
                                ServiceSpotBusinessEditScreen(spot: spot),
                          ),
                        );

                        if (updatedSpot != null && mounted) {
                          setState(() => spot = updatedSpot);
                        }
                      },
                      icon: const Icon(Icons.edit_note),
                      label: const CcsText('Edit Service Info'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side: const BorderSide(color: blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                if (spot.hasContactInfo) ...[
                  const SizedBox(height: 16),
                  SpotContactSection(spot: spot),
                ],
                const SizedBox(height: 18),
                if (spot.isTemporary)
                  const Divider(height: 24, color: Color(0xFF263647)),
                SpotReviewsSection(spot: spot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
