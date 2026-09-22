import 'package:ccs_app/features/moderation/controllers/admin_edit_spot_view_state.dart';
import 'package:ccs_app/features/moderation/widgets/admin_edit_spot_content.dart';
import 'package:ccs_app/features/moderation/controllers/admin_edit_spot_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart' show maxSpotGalleryPhotos;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/events/widgets/event_schedule.dart'
    show TemporarySpotScheduleCard;
import 'package:ccs_app/features/map/screens/location_picker_screen.dart'
    show SpotLocationPicker;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot, currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/moderation/data/spot_review_lease.dart'
    show SpotReviewLease;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show showAdminActionError;
import 'package:ccs_app/features/profile/screens/settings_screen.dart'
    show SettingsSwitchTile;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData, defaultServiceOpeningHours;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions, spotCategorySupportsContacts;
import 'package:ccs_app/features/spots/widgets/opening_hours_editor.dart'
    show OpeningHoursEditor;
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart'
    show primarySpotCategory;
import 'package:ccs_app/features/spots/widgets/spot_owner_selector.dart'
    show SpotOwnerSelector;
import 'package:ccs_app/features/spots/widgets/spot_category_dropdown.dart'
    show SpotCategoryDropdown;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/widgets/form_fields.dart'
    show AddSpotSection, CcsTextField;

Future<void> openAdminEditSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterSave = false,
  SpotReviewLease? reviewLease,
}) async {
  if (currentUser.role == UserRole.moderator &&
      !currentUserCanModerateSpot(spot)) {
    showAdminActionError(
      context,
      message: trText('This spot is outside your assigned countries'),
      error: 'regional-moderator-scope',
    );
    return;
  }

  final saved = await Navigator.push<bool>(
    context,
    appPageRoute(
      builder: (_) => AdminEditSpotScreen(spot: spot, reviewLease: reviewLease),
    ),
  );

  if (saved == true && popAfterSave && context.mounted) {
    Navigator.pop(context);
  }
}

class AdminEditSpotScreen extends StatefulWidget
    implements AdminEditSpotInputs {
  @override
  final CarSpot spot;
  @override
  final SpotReviewLease? reviewLease;

  const AdminEditSpotScreen({super.key, required this.spot, this.reviewLease});

  @override
  State<AdminEditSpotScreen> createState() => _AdminEditSpotScreenState();
}

class _AdminEditSpotScreenState extends State<AdminEditSpotScreen>
    with LanguageReactiveState
    implements AdminEditSpotViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  late final AdminEditSpotContentActions content = AdminEditSpotContent(this);

  @override
  late final AdminEditSpotControllerActions controller =
      AdminEditSpotController(this);

  @override
  late final TextEditingController nameController;
  @override
  late final TextEditingController cityController;
  @override
  late final TextEditingController latController;
  @override
  late final TextEditingController lngController;
  @override
  late final TextEditingController descriptionController;
  @override
  late final TextEditingController reelController;
  @override
  late final TextEditingController phoneController;
  @override
  late final TextEditingController instagramController;
  @override
  late final TextEditingController emailController;
  @override
  late String selectedCategory;
  @override
  late bool verifiedOnlySpot;
  @override
  late bool isTemporarySpot;
  @override
  DateTime? temporaryStartsAt;
  @override
  DateTime? temporaryExpiresAt;
  @override
  bool temporaryShowOnMapAtEnabled = false;
  @override
  DateTime? temporaryShowOnMapAt;
  @override
  late final List<String> existingPhotoUrls;
  @override
  final List<String> newPhotoPaths = [];
  @override
  late Map<int, OpeningHoursData> openingHours;
  @override
  SpotOwnerAssignment? selectedOwner;
  @override
  bool isSaving = false;
  @override
  bool isUpdatingEditLocation = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.spot.name);
    cityController = TextEditingController(text: widget.spot.cityCountry);
    latController = TextEditingController(
      text: widget.spot.coordinates.latitude.toStringAsFixed(6),
    );
    lngController = TextEditingController(
      text: widget.spot.coordinates.longitude.toStringAsFixed(6),
    );
    descriptionController = TextEditingController(
      text: widget.spot.description,
    );
    reelController = TextEditingController(text: widget.spot.reelLink);
    phoneController = TextEditingController(text: widget.spot.contactPhone);
    instagramController = TextEditingController(
      text: widget.spot.contactInstagram,
    );
    emailController = TextEditingController(text: widget.spot.contactEmail);
    if (widget.spot.ownerUid.isNotEmpty ||
        widget.spot.ownerUsername.isNotEmpty) {
      selectedOwner = SpotOwnerAssignment(
        uid: widget.spot.ownerUid,
        username: widget.spot.ownerUsername.isNotEmpty
            ? widget.spot.ownerUsername
            : widget.spot.ownerUid,
      );
    }
    selectedCategory = primarySpotCategory(widget.spot);
    verifiedOnlySpot = widget.spot.verifiedOnly;
    isTemporarySpot = widget.spot.isTemporary;
    temporaryStartsAt = widget.spot.startsAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.startsAtMillis!);
    temporaryExpiresAt = widget.spot.expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.expiresAtMillis!);
    temporaryShowOnMapAtEnabled = widget.spot.showOnMapAtMillis != null;
    temporaryShowOnMapAt = widget.spot.showOnMapAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.spot.showOnMapAtMillis!);
    openingHours = widget.spot.openingHours.isEmpty
        ? defaultServiceOpeningHours()
        : {...widget.spot.openingHours};
    existingPhotoUrls = <String>[];

    void addExistingUrl(String value) {
      final cleanValue = value.trim();
      if (cleanValue.isNotEmpty &&
          isNetworkUrl(cleanValue) &&
          !existingPhotoUrls.contains(cleanValue)) {
        existingPhotoUrls.add(cleanValue);
      }
    }

    for (final photoUrl in widget.spot.photoUrls) {
      addExistingUrl(photoUrl);
    }
    addExistingUrl(widget.spot.photoUrl);
  }

  @override
  void dispose() {
    nameController.dispose();
    cityController.dispose();
    latController.dispose();
    lngController.dispose();
    descriptionController.dispose();
    reelController.dispose();
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = controller.totalPhotoCount < maxSpotGalleryPhotos;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Edit Spot'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          AddSpotSection(
            title: 'Basic info',
            children: [
              CcsTextField(
                controller: nameController,
                label: 'Spot name',
                hint: 'Andrejsala Harbor',
                icon: Icons.place,
              ),
              CcsTextField(
                controller: cityController,
                label: 'City / country',
                hint: 'Riga, Latvia',
                icon: Icons.location_city,
              ),
              SpotLocationPicker(
                hasLocation: true,
                isBusy: isUpdatingEditLocation,
                statusText: isUpdatingEditLocation
                    ? 'Detecting city/country...'
                    : '${cityController.text.trim().isEmpty ? 'Unknown location' : cityController.text.trim()} • ${latController.text.trim()}, ${lngController.text.trim()}',
                onMapTap: controller.chooseEditedLocationOnMap,
                onAddressTap: controller.chooseEditedLocationByAddress,
                onCurrentTap: controller.chooseEditedCurrentLocation,
              ),
              CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: '',
                icon: Icons.notes,
                maxLines: 4,
              ),
              CcsTextField(
                controller: reelController,
                label: 'Video link',
                hint: 'https://instagram.com/reel/...',
                icon: Icons.play_circle,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (spotCategorySupportsContacts(selectedCategory)) ...[
            AddSpotSection(
              title: 'Contacts',
              children: [
                CcsTextField(
                  controller: phoneController,
                  label: 'Phone',
                  hint: '+371 20 000 000',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                CcsTextField(
                  controller: instagramController,
                  label: 'Instagram',
                  hint: '@ccs.lv or https://instagram.com/ccs.lv',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.url,
                ),
                CcsTextField(
                  controller: emailController,
                  label: 'Email',
                  hint: 'hello@ccs.lv',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                SpotOwnerSelector(
                  selectedOwner: selectedOwner,
                  onChanged: (owner) => setState(() => selectedOwner = owner),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AddSpotSection(
              title: 'Opening hours',
              children: [
                OpeningHoursEditor(
                  openingHours: openingHours,
                  onChanged: (value) => setState(() => openingHours = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          AddSpotSection(
            title: 'Category',
            children: [
              SpotCategoryDropdown(
                value: selectedCategory,
                categories: spotCategoryOptions,
                onChanged: (category) {
                  if (category == null) {
                    return;
                  }
                  setState(() => selectedCategory = category);
                },
              ),
            ],
          ),
          if (currentUserCanUseVerifiedOnlySpots) ...[
            const SizedBox(height: 16),
            AddSpotSection(
              title: 'Visibility',
              children: [
                SettingsSwitchTile(
                  icon: Icons.verified_user,
                  title: 'Verified only',
                  subtitle:
                      'Only verified users and admins can see this spot after approval',
                  value: verifiedOnlySpot,
                  onChanged: (value) =>
                      setState(() => verifiedOnlySpot = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Event schedule',
            children: [
              TemporarySpotScheduleCard(
                enabled: isTemporarySpot,
                startsAt: temporaryStartsAt,
                expiresAt: temporaryExpiresAt,
                showOnMapAtEnabled: temporaryShowOnMapAtEnabled,
                showOnMapAt: temporaryShowOnMapAt,
                onEnabledChanged: (value) {
                  setState(() {
                    isTemporarySpot = value;
                    if (value && temporaryStartsAt == null) {
                      final start = DateTime.now().add(
                        const Duration(hours: 1),
                      );
                      temporaryStartsAt = start;
                      temporaryExpiresAt = start.add(const Duration(hours: 3));
                    }
                    if (!value) {
                      temporaryShowOnMapAtEnabled = false;
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onShowOnMapAtEnabledChanged: (value) {
                  setState(() {
                    temporaryShowOnMapAtEnabled = value;
                    if (value &&
                        temporaryShowOnMapAt == null &&
                        temporaryStartsAt != null) {
                      temporaryShowOnMapAt = DateTime(
                        temporaryStartsAt!.year,
                        temporaryStartsAt!.month,
                        temporaryStartsAt!.day,
                      );
                    }
                    if (!value) {
                      temporaryShowOnMapAt = null;
                    }
                  });
                },
                onPickStart: controller.chooseTemporaryStart,
                onPickEnd: controller.chooseTemporaryEnd,
                onPickShowOnMapAt: controller.chooseTemporaryShowOnMapAt,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Photos',
            children: [
              InkWell(
                onTap: canAddMore ? controller.addPhoto : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: controller.totalPhotoCount > 0
                          ? blue.withValues(alpha: 0.7)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          canAddMore ? Icons.add_photo_alternate : Icons.check,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CcsText(
                              controller.totalPhotoCount == 0
                                  ? 'Upload photos'
                                  : '$controller.totalPhotoCount/$maxSpotGalleryPhotos photos selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            CcsText(
                              canAddMore
                                  ? 'Add or remove spot photos. The first photo becomes the Explore thumbnail.'
                                  : 'Maximum 4 photos selected. First photo is the spot thumbnail.',
                              style: const TextStyle(
                                color: Colors.white54,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        canAddMore ? Icons.chevron_right : Icons.lock,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.totalPhotoCount > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (
                      var index = 0;
                      index < existingPhotoUrls.length;
                      index++
                    )
                      content.photoThumb(
                        index: index,
                        label: index == 0 ? 'Cover' : '${index + 1}',
                        source: existingPhotoUrls[index],
                        isLocal: false,
                        onRemove: () => controller.removeExistingPhotoAt(index),
                      ),
                    for (var index = 0; index < newPhotoPaths.length; index++)
                      content.photoThumb(
                        index: existingPhotoUrls.length + index,
                        label: existingPhotoUrls.length + index == 0
                            ? 'Cover'
                            : '${existingPhotoUrls.length + index + 1}',
                        source: newPhotoPaths[index],
                        isLocal: true,
                        onRemove: () => controller.removeNewPhotoAt(index),
                      ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : controller.saveSpot,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.save),
              label: CcsText(isSaving ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
