import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/partners/data/partners_repository.dart'
    show
        ccsPartnersCollection,
        currentUserCanManagePartners,
        uploadPartnerImage;
import 'package:ccs_app/features/partners/models/partner.dart' show CcsPartner;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;

class AddPartnerScreen extends StatefulWidget {
  final CcsPartner? partner;

  const AddPartnerScreen({super.key, this.partner});

  @override
  State<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

class _AddPartnerScreenState extends State<AddPartnerScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController bioController;
  late final TextEditingController phoneController;
  late final TextEditingController websiteController;
  late final TextEditingController instagramController;
  late final TextEditingController telegramController;
  String? logoPath;
  late String existingLogoUrl;
  final List<String> galleryPaths = [];
  late List<String> existingGalleryUrls;
  late bool active;
  bool saving = false;

  bool get isEditing => widget.partner != null;

  @override
  void initState() {
    super.initState();
    final partner = widget.partner;
    nameController = TextEditingController(text: partner?.name ?? '');
    bioController = TextEditingController(text: partner?.bio ?? '');
    phoneController = TextEditingController(text: partner?.phone ?? '');
    websiteController = TextEditingController(text: partner?.website ?? '');
    instagramController = TextEditingController(text: partner?.instagram ?? '');
    telegramController = TextEditingController(text: partner?.telegram ?? '');
    existingLogoUrl = partner?.logoUrl ?? '';
    existingGalleryUrls = [...?partner?.photoUrls];
    active = partner?.active ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    bioController.dispose();
    phoneController.dispose();
    websiteController.dispose();
    instagramController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  Future<void> pickLogo() async {
    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1.6,
      cropShape: PhotoCropShape.rectangle,
    );
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() => logoPath = path);
  }

  Future<void> addGalleryPhoto() async {
    if (existingGalleryUrls.length + galleryPaths.length >= 4) return;
    final path = await pickPhotoFromPhone(context, cropPhoto: false);
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      if (existingGalleryUrls.length + galleryPaths.length < 4) {
        galleryPaths.add(path);
      }
    });
  }

  Future<void> removePartner() async {
    if (!isEditing || saving || !currentUserCanManagePartners) return;

    final partner = widget.partner!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const CcsText('Remove partner?'),
          content: CcsText(
            'This will permanently remove ${partner.name} from CCS Partners. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const CcsText('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const CcsText('Remove partner'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => saving = true);
    try {
      await ccsPartnersCollection()
          .doc(partner.id)
          .debugDelete('partners: admin delete partner');

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText('${partner.name} removed.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText('Could not remove partner: $error'),
        ),
      );
    }
  }

  Future<void> savePartner() async {
    if (saving || !currentUserCanManagePartners) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    if ((logoPath == null || logoPath!.trim().isEmpty) &&
        existingLogoUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText('Partner logo is required.'),
        ),
      );
      return;
    }

    setState(() => saving = true);
    try {
      final ref = isEditing
          ? ccsPartnersCollection().doc(widget.partner!.id)
          : ccsPartnersCollection().doc();

      var logoUrl = existingLogoUrl;
      if (logoPath != null && logoPath!.trim().isNotEmpty) {
        logoUrl = await uploadPartnerImage(
          partnerId: ref.id,
          localPhotoPath: logoPath!,
          logo: true,
        );
      }

      final galleryUrls = <String>[...existingGalleryUrls];
      for (
        var index = 0;
        index < galleryPaths.length && galleryUrls.length < 4;
        index++
      ) {
        galleryUrls.add(
          await uploadPartnerImage(
            partnerId: ref.id,
            localPhotoPath: galleryPaths[index],
            logo: false,
            photoIndex: galleryUrls.length,
          ),
        );
      }

      final partnerData = <String, dynamic>{
        'name': nameController.text.trim(),
        'logoUrl': logoUrl,
        'bio': bioController.text.trim(),
        'phone': phoneController.text.trim(),
        'website': websiteController.text.trim(),
        'instagram': instagramController.text.trim(),
        'telegram': telegramController.text.trim(),
        'photoUrls': galleryUrls,
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isEditing) {
        await ref.debugUpdate(partnerData, 'partners: admin update partner');
      } else {
        partnerData.addAll({
          'createdByUid': currentUser.uid,
          'createdByUsername': currentUser.username,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await ref.debugSet(partnerData, null, 'partners: admin create partner');
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(isEditing ? 'Partner updated.' : 'Partner added.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            isEditing
                ? 'Could not update partner: $error'
                : 'Could not add partner: $error',
          ),
        ),
      );
    }
  }

  Widget field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
      minLines: maxLines > 1 ? 3 : 1,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white),
      validator: required
          ? (value) =>
                (value ?? '').trim().isEmpty ? '$label is required.' : null
          : null,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!currentUserCanManagePartners) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: CcsText(isEditing ? 'Edit partner' : 'Add partner'),
          backgroundColor: Colors.transparent,
        ),
        body: const Center(
          child: CcsText(
            'Only administrators can manage partners.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(isEditing ? 'Edit partner' : 'Add partner'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const CcsText(
              'Logo *',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: saving ? null : pickLogo,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: panelGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: logoPath == null
                        ? blue.withValues(alpha: 0.45)
                        : blue,
                  ),
                ),
                child: logoPath != null
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.file(File(logoPath!), fit: BoxFit.contain),
                      )
                    : existingLogoUrl.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.network(
                          existingLogoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: blue,
                          ),
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: blue),
                          SizedBox(height: 6),
                          CcsText(
                            'Upload partner logo',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            field(
              nameController,
              'Partner name',
              Icons.business_outlined,
              required: true,
            ),
            const SizedBox(height: 12),
            field(
              bioController,
              'About partner',
              Icons.notes_outlined,
              maxLines: 5,
              maxLength: 1200,
            ),
            const SizedBox(height: 12),
            field(
              phoneController,
              'Partner phone',
              Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            field(
              websiteController,
              'Partner website',
              Icons.language,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            field(
              instagramController,
              'Partner Instagram',
              Icons.camera_alt_outlined,
            ),
            const SizedBox(height: 12),
            field(telegramController, 'Partner Telegram', Icons.send_outlined),
            const SizedBox(height: 8),
            SwitchListTile(
              value: active,
              onChanged: saving
                  ? null
                  : (value) => setState(() => active = value),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: blue,
              title: const CcsText(
                'Active partner',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const CcsText(
                'Inactive partners stay editable for admins but are hidden from users.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: CcsText(
                    'Photo gallery',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                CcsText(
                  '${existingGalleryUrls.length + galleryPaths.length}/4',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (existingGalleryUrls.isNotEmpty || galleryPaths.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.35,
                ),
                itemCount: existingGalleryUrls.length + galleryPaths.length,
                itemBuilder: (context, index) {
                  final remote = index < existingGalleryUrls.length;
                  final localIndex = index - existingGalleryUrls.length;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: remote
                            ? Image.network(
                                existingGalleryUrls[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: Colors.white10,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                ),
                              )
                            : Image.file(
                                File(galleryPaths[localIndex]),
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filled(
                          visualDensity: VisualDensity.compact,
                          onPressed: saving
                              ? null
                              : () => setState(() {
                                  if (remote) {
                                    existingGalleryUrls.removeAt(index);
                                  } else {
                                    galleryPaths.removeAt(localIndex);
                                  }
                                }),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ],
                  );
                },
              ),
            if (existingGalleryUrls.isNotEmpty || galleryPaths.isNotEmpty)
              const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  saving ||
                      existingGalleryUrls.length + galleryPaths.length >= 4
                  ? null
                  : addGalleryPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: CcsText(
                existingGalleryUrls.length + galleryPaths.length >= 4
                    ? 'Maximum 4 photos'
                    : 'Add gallery photo',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : savePartner,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: CcsText(
                  saving
                      ? (isEditing ? 'Saving changes...' : 'Saving partner...')
                      : (isEditing ? 'Save changes' : 'Save partner'),
                ),
              ),
            ),
            if (isEditing) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.55),
                    ),
                  ),
                  onPressed: saving ? null : removePartner,
                  icon: const Icon(Icons.delete_outline),
                  label: const CcsText('Remove partner'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
