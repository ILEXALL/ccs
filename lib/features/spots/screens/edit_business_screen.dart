import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanManageSpotBusiness;
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData, defaultServiceOpeningHours, openingHoursToFirebase;
import 'package:ccs_app/features/spots/widgets/opening_hours_editor.dart'
    show OpeningHoursEditor;
import 'package:ccs_app/shared/widgets/form_fields.dart'
    show AddSpotSection, CcsTextField;

class ServiceSpotBusinessEditScreen extends StatefulWidget {
  final CarSpot spot;

  const ServiceSpotBusinessEditScreen({super.key, required this.spot});

  @override
  State<ServiceSpotBusinessEditScreen> createState() =>
      _ServiceSpotBusinessEditScreenState();
}

class _ServiceSpotBusinessEditScreenState
    extends State<ServiceSpotBusinessEditScreen> {
  late final TextEditingController phoneController;
  late final TextEditingController instagramController;
  late final TextEditingController emailController;
  late Map<int, OpeningHoursData> openingHours;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    phoneController = TextEditingController(text: widget.spot.contactPhone);
    instagramController = TextEditingController(
      text: widget.spot.contactInstagram,
    );
    emailController = TextEditingController(text: widget.spot.contactEmail);
    openingHours = widget.spot.openingHours.isEmpty
        ? defaultServiceOpeningHours()
        : {...widget.spot.openingHours};
  }

  @override
  void dispose() {
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> saveBusinessInfo() async {
    if (isSaving) {
      return;
    }

    if (!currentUserCanManageSpotBusiness(widget.spot)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Only the assigned owner or an admin can edit this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final updatedSpot = widget.spot.copyWith(
        contactPhone: phoneController.text.trim(),
        contactInstagram: instagramController.text.trim(),
        contactEmail: emailController.text.trim(),
        openingHours: openingHours,
      );

      await spotsCollection().doc(widget.spot.id).debugUpdate({
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'businessEditedBy': currentUser.username,
        'businessEditedByUid': currentUser.uid,
        'businessEditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final visibleUpdatedSpot = updatedSpot;

      reviewSpots.value = reviewSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      submittedSpots.value = submittedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      savedSpots.value = savedSpots.value
          .map(
            (item) => isSameSpot(item, widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Service info updated.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context, updatedSpot);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not update service info: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Service Info'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
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
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveBusinessInfo,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.save),
              label: CcsText(isSaving ? 'Saving...' : 'Save Service Info'),
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
