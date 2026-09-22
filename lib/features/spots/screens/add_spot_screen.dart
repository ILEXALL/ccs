import 'package:ccs_app/features/spots/controllers/add_spot_view_state.dart';
import 'package:ccs_app/features/spots/widgets/add_spot_content.dart';
import 'package:ccs_app/features/spots/controllers/add_spot_controller.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show memberSpotGroups;
import 'package:ccs_app/features/events/widgets/event_schedule.dart'
    show TemporarySpotScheduleCard;
import 'package:ccs_app/features/map/screens/location_picker_screen.dart'
    show SpotLocationPicker, SpotPhotoPickerField;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/profile/screens/settings_screen.dart'
    show SettingsSwitchTile;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment;
import 'package:ccs_app/features/spots/data/spot_regions.dart'
    show SpotLocationRegion;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData, defaultServiceOpeningHours;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategorySupportsContacts;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/features/spots/widgets/opening_hours_editor.dart'
    show OpeningHoursEditor;
import 'package:ccs_app/features/spots/widgets/spot_owner_selector.dart'
    show SpotOwnerSelector;
import 'package:ccs_app/features/spots/widgets/spot_category_dropdown.dart'
    show SpotCategoryDropdown;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;
import 'package:ccs_app/shared/widgets/form_fields.dart'
    show AddSpotSection, CcsTextField;

class AddSpotScreen extends StatefulWidget implements AddSpotInputs {
  @override
  final bool eventMode;
  @override
  final bool privateEvent;
  const AddSpotScreen({
    super.key,
    this.eventMode = false,
    this.privateEvent = false,
  });

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen>
    implements AddSpotViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  late final AddSpotContentActions content = AddSpotContent(this);

  @override
  late final AddSpotControllerActions controller = AddSpotController(this);

  @override
  final nameController = TextEditingController();
  @override
  final cityController = TextEditingController();
  @override
  final addressController = TextEditingController();
  @override
  final descriptionController = TextEditingController();
  @override
  final reelController = TextEditingController();
  @override
  final phoneController = TextEditingController();
  @override
  final instagramController = TextEditingController();
  @override
  final emailController = TextEditingController();
  @override
  final addedByController = TextEditingController();

  @override
  String selectedCategory = 'Photo';
  @override
  LatLng? selectedLocation;
  @override
  SpotLocationRegion? selectedRegion;
  @override
  int locationLookupRevision = 0;
  @override
  String detectedCityCountry = 'Choose location to detect city/country';
  @override
  bool isDetectingCityCountry = false;
  @override
  bool isUsingCurrentLocation = false;
  @override
  final List<String> selectedPhotoPaths = [];
  @override
  bool verifiedOnlySpot = false;
  @override
  bool isTemporarySpot = false;
  @override
  bool groupVisibility = false;
  @override
  final Set<String> selectedGroupIds = {};
  @override
  DateTime? temporaryStartsAt;
  @override
  DateTime? temporaryExpiresAt;
  @override
  bool temporaryShowOnMapAtEnabled = false;
  @override
  DateTime? temporaryShowOnMapAt;
  @override
  Map<int, OpeningHoursData> openingHours = defaultServiceOpeningHours();
  @override
  SpotOwnerAssignment? selectedOwner;
  @override
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    addedByController.text = currentUser.username;
    isTemporarySpot = widget.eventMode;
    groupVisibility = widget.privateEvent;
    if (widget.eventMode) {
      selectedCategory = 'Meet';
      temporaryStartsAt = DateTime.now().add(const Duration(hours: 1));
      temporaryExpiresAt = temporaryStartsAt!.add(const Duration(hours: 3));
    }
    memberSpotGroups.addListener(controller.groupMembershipChanged);
  }

  @override
  void dispose() {
    memberSpotGroups.removeListener(controller.groupMembershipChanged);
    nameController.dispose();
    cityController.dispose();
    addressController.dispose();
    descriptionController.dispose();
    reelController.dispose();
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    addedByController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const CcsAppBarLogo(),
            backgroundColor: Colors.transparent,
            foregroundColor: blue,
            actions: ccsAppBarActions(),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: blue.withValues(alpha: 0.24)),
                    ),
                    child: const Icon(
                      Icons.add_location_alt,
                      color: blue,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CcsText(
                          trText(
                            widget.privateEvent
                                ? 'Add Private Event'
                                : widget.eventMode
                                ? 'Add Event'
                                : 'Add Spot',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 0),
                        CcsText(
                          trText(
                            'Create a pin for review or publish instantly as staff.',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PendingBadge(
                    status: userRoleIsStaff(currentUser.role)
                        ? SpotStatus.approved
                        : SpotStatus.pending,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AddSpotSection(
                title: widget.eventMode ? 'Event details' : 'Spot details',
                children: [
                  CcsTextField(
                    controller: nameController,
                    label: widget.eventMode ? 'Event name' : 'Spot name',
                    hint: 'Andrejsala Harbor',
                    icon: Icons.place,
                  ),
                  SpotCategoryDropdown(
                    value: selectedCategory,
                    categories: controller.categoryOptions,
                    onChanged: (category) {
                      if (category == null) {
                        return;
                      }

                      setState(() => selectedCategory = category);
                    },
                  ),
                  SpotLocationPicker(
                    hasLocation: selectedLocation != null,
                    isBusy: isDetectingCityCountry || isUsingCurrentLocation,
                    statusText: isUsingCurrentLocation
                        ? 'Getting your GPS position...'
                        : isDetectingCityCountry
                        ? 'Detecting city/country...'
                        : selectedLocation == null
                        ? 'Choose by map, address, or GPS'
                        : detectedCityCountry,
                    onMapTap: controller.chooseLocation,
                    onAddressTap: controller.findExactAddress,
                    onCurrentTap: controller.useCurrentLocation,
                  ),
                  CcsTextField(
                    controller: descriptionController,
                    label: 'Description',
                    hint: '',
                    icon: Icons.notes,
                    maxLines: 3,
                  ),
                  if (currentUserCanUseVerifiedOnlySpots)
                    SettingsSwitchTile(
                      icon: Icons.verified_user,
                      title: 'Verified only',
                      subtitle:
                          'Only verified users and admins can see this spot',
                      value: verifiedOnlySpot,
                      onChanged: (value) =>
                          setState(() => verifiedOnlySpot = value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.eventMode)
                AddSpotSection(
                  title: 'Event schedule',
                  children: [
                    if (widget.privateEvent) content.temporaryAudiencePicker(),
                    TemporarySpotScheduleCard(
                      showTypeSwitch: false,
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
                            temporaryExpiresAt = start.add(
                              const Duration(hours: 3),
                            );
                          }
                          if (!value) {
                            groupVisibility = false;
                            selectedGroupIds.clear();
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
              const SizedBox(height: 10),
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
                    if (userRoleIsStaff(currentUser.role))
                      SpotOwnerSelector(
                        selectedOwner: selectedOwner,
                        onChanged: (owner) =>
                            setState(() => selectedOwner = owner),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                AddSpotSection(
                  title: 'Opening hours',
                  children: [
                    OpeningHoursEditor(
                      openingHours: openingHours,
                      onChanged: (value) =>
                          setState(() => openingHours = value),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              AddSpotSection(
                title: 'Media',
                children: [
                  SpotPhotoPickerField(
                    photoPaths: selectedPhotoPaths,
                    onAddPhoto: controller.choosePhoto,
                    onRemovePhoto: controller.removePhotoAt,
                  ),
                  CcsTextField(
                    controller: reelController,
                    label: 'Video link',
                    hint: 'https://instagram.com/reel/...',
                    icon: Icons.play_circle,
                    keyboardType: TextInputType.url,
                  ),
                  CcsTextField(
                    controller: addedByController,
                    label: 'Added by',
                    hint: 'Your profile nickname',
                    icon: Icons.person,
                    readOnly: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : controller.submitSpot,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isSubmitting ? Icons.hourglass_top : Icons.send),
                      const SizedBox(width: 10),
                      CcsText(
                        trText(
                          isSubmitting
                              ? (userRoleIsStaff(currentUser.role)
                                    ? 'Creating spot...'
                                    : 'Submitting for review...')
                              : (userRoleIsStaff(currentUser.role)
                                    ? 'Create Spot'
                                    : 'Submit for Review'),
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PendingBadge extends StatelessWidget {
  final SpotStatus status;

  const PendingBadge({super.key, this.status = SpotStatus.pending});

  String get label {
    switch (status) {
      case SpotStatus.pending:
        return 'pending';
      case SpotStatus.approved:
        return 'live';
      case SpotStatus.rejected:
        return 'rejected';
      case SpotStatus.edited:
        return 'edited';
    }
  }

  Color get color {
    switch (status) {
      case SpotStatus.pending:
        return blue;
      case SpotStatus.approved:
        return Colors.greenAccent;
      case SpotStatus.rejected:
        return Colors.redAccent;
      case SpotStatus.edited:
        return Colors.orangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: CcsText(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
