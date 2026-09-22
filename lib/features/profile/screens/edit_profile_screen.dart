import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart'
    show
        UsernameAvailability,
        checkUsernameAvailabilityForCurrentUser,
        cleanProfileUsername,
        maxProfileUsernameLength,
        minProfileUsernameLength,
        usernameAvailabilityColor,
        usernameAvailabilityIcon,
        usernameAvailabilityText,
        usernameKey;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/profile/models/profile_validation.dart'
    show profileRegionIsComplete, requiredRegionMessage;
import 'package:ccs_app/features/profile/models/user_profile.dart'
    show UserProfileData;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/countries.dart'
    show
        allSupportedCountryNames,
        canonicalSpotCountryName,
        countryFlagEmoji,
        countryIsoCode,
        localizedCountryName;
import 'package:ccs_app/shared/widgets/form_fields.dart'
    show AddSpotSection, CcsTextField;

class EditProfileScreen extends StatefulWidget {
  final UserProfileData profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController countryController;
  late final TextEditingController usernameController;
  late final TextEditingController cityController;
  late final TextEditingController bioController;
  late final TextEditingController instagramController;
  late final TextEditingController tiktokController;
  late final TextEditingController telegramController;
  String? avatarPath;
  Timer? usernameAvailabilityDebounce;
  UsernameAvailability usernameAvailability = UsernameAvailability.unchanged;

  bool get canSaveProfile {
    return usernameAvailability == UsernameAvailability.unchanged ||
        usernameAvailability == UsernameAvailability.available;
  }

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.profile.username);
    cityController = TextEditingController(text: widget.profile.city);
    countryController = TextEditingController(text: widget.profile.country);
    bioController = TextEditingController(text: widget.profile.bio);
    instagramController = TextEditingController(text: widget.profile.instagram);
    tiktokController = TextEditingController(text: widget.profile.tiktok);
    telegramController = TextEditingController(text: widget.profile.telegram);
    avatarPath = widget.profile.avatarPath;
    usernameController.addListener(queueUsernameAvailabilityCheck);
  }

  @override
  void dispose() {
    usernameAvailabilityDebounce?.cancel();
    usernameController.removeListener(queueUsernameAvailabilityCheck);
    usernameController.dispose();
    cityController.dispose();
    countryController.dispose();
    bioController.dispose();
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  void queueUsernameAvailabilityCheck() {
    usernameAvailabilityDebounce?.cancel();

    final cleanUsername = cleanProfileUsername(usernameController.text);

    if (cleanUsername.length < minProfileUsernameLength ||
        cleanUsername.length > maxProfileUsernameLength) {
      setState(() => usernameAvailability = UsernameAvailability.invalid);
      return;
    }

    if (usernameKey(cleanUsername) == usernameKey(widget.profile.username)) {
      setState(() => usernameAvailability = UsernameAvailability.unchanged);
      return;
    }

    setState(() => usernameAvailability = UsernameAvailability.checking);

    usernameAvailabilityDebounce = Timer(const Duration(milliseconds: 450), () {
      checkUsernameAvailability(cleanUsername);
    });
  }

  Future<void> checkUsernameAvailability(String usernameToCheck) async {
    final checkedKey = usernameKey(usernameToCheck);
    final availability = await checkUsernameAvailabilityForCurrentUser(
      usernameToCheck,
      currentUsername: widget.profile.username,
    );

    if (!mounted || usernameKey(usernameController.text) != checkedKey) {
      return;
    }

    setState(() => usernameAvailability = availability);
  }

  Future<void> chooseAvatar() async {
    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (!mounted || path == null) {
      return;
    }

    setState(() => avatarPath = path);
  }

  Future<void> saveProfile() async {
    if (!profileRegionIsComplete(cityController.text, countryController.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: CcsText(requiredRegionMessage)));
      return;
    }
    if (!canSaveProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            usernameAvailabilityText(usernameAvailability),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      UserProfileData(
        username: usernameController.text.trim().isEmpty
            ? currentUser.username
            : cleanProfileUsername(usernameController.text),
        city: cityController.text.trim(),
        country: canonicalSpotCountryName(countryController.text.trim()),
        bio: bioController.text.trim().isEmpty
            ? 'Find. Drive. Shoot.'
            : bioController.text.trim(),
        instagram: instagramController.text.trim(),
        tiktok: tiktokController.text.trim(),
        telegram: telegramController.text.trim(),
        avatarPath: avatarPath,
        photoUrl: widget.profile.photoUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Edit Profile'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: chooseAvatar,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: blue.withValues(alpha: 0.5)),
                    ),
                    child: ClipOval(
                      child: localFileExists(avatarPath)
                          ? Image.file(
                              File(avatarPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return const Icon(
                                  Icons.add_a_photo,
                                  color: blue,
                                  size: 34,
                                );
                              },
                            )
                          : (isNetworkUrl(avatarPath) ||
                                (currentUser.photoUrl?.trim().isNotEmpty ??
                                    false))
                          ? Image.network(
                              isNetworkUrl(avatarPath)
                                  ? avatarPath!
                                  : currentUser.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return const Icon(
                                  Icons.add_a_photo,
                                  color: blue,
                                  size: 34,
                                );
                              },
                            )
                          : const Icon(
                              Icons.add_a_photo,
                              color: blue,
                              size: 34,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const CcsText(
                  'Tap to change avatar',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Profile info',
            children: [
              CcsTextField(
                controller: usernameController,
                label: 'Nickname',
                hint: 'riga_driver',
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    usernameAvailabilityIcon(usernameAvailability),
                    color: usernameAvailabilityColor(usernameAvailability),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CcsText(
                      usernameAvailabilityText(usernameAvailability),
                      style: TextStyle(
                        color: usernameAvailabilityColor(usernameAvailability),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: const ValueKey('profile-country'),
                initialValue: countryIsoCode(countryController.text),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: communityText(
                    en: 'Country',
                    ru: 'Страна',
                    lv: 'Valsts',
                  ),
                  prefixIcon: const Icon(Icons.public, color: blue),
                ),
                items: allSupportedCountryNames()
                    .map(
                      (country) => DropdownMenuItem<String>(
                        value: countryIsoCode(country),
                        child: CcsText(
                          countryFlagEmoji(country) +
                              ' ' +
                              localizedCountryName(country),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (code) {
                  if (code != null)
                    countryController.text = canonicalSpotCountryName(code);
                },
                validator: (value) =>
                    value == null ? requiredRegionMessage : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('profile-city'),
                controller: cityController,
                decoration: InputDecoration(
                  labelText: communityText(
                    en: 'City',
                    ru: 'Город',
                    lv: 'Pilsēta',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CcsText(
                communityText(
                  en: 'You can correct your automatically detected location here. Your country is used for your chat flag.',
                  ru: 'Здесь можно исправить автоматически определённое местоположение. Страна используется для флага в чате.',
                  lv: 'Šeit varat labot automātiski noteikto atrašanās vietu. Valsts tiek izmantota jūsu karogam tērzēšanā.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              CcsTextField(
                controller: bioController,
                label: 'About you',
                hint: 'Short description',
                icon: Icons.notes,
                autoGrow: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Social links',
            children: [
              CcsTextField(
                controller: instagramController,
                label: 'Instagram',
                hint: 'https://instagram.com/...',
                icon: Icons.camera_alt,
                keyboardType: TextInputType.url,
              ),
              CcsTextField(
                controller: tiktokController,
                label: 'TikTok',
                hint: 'https://tiktok.com/@...',
                icon: Icons.music_note,
                keyboardType: TextInputType.url,
              ),
              CcsTextField(
                controller: telegramController,
                label: 'Telegram',
                hint: 'https://t.me/...',
                icon: Icons.send,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: canSaveProfile ? saveProfile : null,
              icon: const Icon(Icons.check),
              label: const CcsText('Save Profile'),
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
