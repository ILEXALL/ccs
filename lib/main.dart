import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// Paste the OAuth 2.0 Web Client ID from Firebase/Google Cloud here.
// It usually looks like: 325709324670-xxxxx.apps.googleusercontent.com
const googleServerClientId =
    '325709324670-cep9b3r2j2mmapmmuougmqai7umvlod6.apps.googleusercontent.com';

// Real Telegram login needs a small backend server.
// Deploy ccs_app/telegram_auth_server, then paste its HTTPS URL here.
const telegramAuthBaseUrl = 'https://y-beige-eta.vercel.app';
const r2PresignUploadUrl =
    'https://ccs-telegram-auth-server.vercel.app/api/r2-presign-upload';
const int maxSpotGalleryPhotos = 4;
const int maxGaragePhotos = 4;
const int r2SpotPhotoMaxLongSide = 1280;
const int r2AvatarPhotoMaxLongSide = 768;
const int r2GaragePhotoMaxLongSide = 1280;
const int r2JpegQuality = 76;
const double garagePhotoAspectRatio = 1.45;

String? googleSignInSetupError;
bool firebaseReady = false;
bool rememberMeEnabled = false;
const rememberMeKey = 'remember_me';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;

    // Google Sign-In needs one setup call before we use the login button.
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: googleServerClientId,
      );
    } catch (error) {
      googleSignInSetupError = error.toString();
    }

    rememberMeEnabled = await loadRememberMePreference();

    final appUser = await loadCurrentFirebaseUser();
    if (appUser != null) {
      startFirebaseSpotSync();
    }
  } catch (error) {
    // Do not let a Firebase/Google services problem crash the app on startup.
    firebaseReady = false;
    googleSignInSetupError = error.toString();
    rememberMeEnabled = false;
  }

  runApp(const CCSApp());
}

class CCSApp extends StatelessWidget {
  const CCSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CCS',
      theme: ThemeData.dark(),
      home:
          firebaseReady &&
              rememberMeEnabled &&
              FirebaseAuth.instance.currentUser != null
          ? const MainScreen()
          : const SplashScreen(),
    );
  }
}

const blue = Color(0xFF1565FF);
const night = Color(0xFF050507);
const panel = Color(0xFF101014);
const photoPickerChannel = MethodChannel('ccs/photo_picker');

const spotCategoryOptions = [
  'Stance',
  'Drift',
  'Photo',
  'Meet',
  'Drive',
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Drag',
  'Food',
];

const contactEnabledSpotCategories = {
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Food',
};

bool spotCategorySupportsContacts(String category) {
  return contactEnabledSpotCategories.contains(category.trim());
}

const weekdayLabels = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

class OpeningHoursData {
  final bool isOpen;
  final String opensAt;
  final String closesAt;

  const OpeningHoursData({
    required this.isOpen,
    required this.opensAt,
    required this.closesAt,
  });

  OpeningHoursData copyWith({
    bool? isOpen,
    String? opensAt,
    String? closesAt,
  }) {
    return OpeningHoursData(
      isOpen: isOpen ?? this.isOpen,
      opensAt: opensAt ?? this.opensAt,
      closesAt: closesAt ?? this.closesAt,
    );
  }

  factory OpeningHoursData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);

    return OpeningHoursData(
      isOpen: data['isOpen'] == true,
      opensAt: stringFromFirebase(data['opensAt'], '08:00'),
      closesAt: stringFromFirebase(data['closesAt'], '20:00'),
    );
  }

  Map<String, Object?> toFirebase() {
    return {
      'isOpen': isOpen,
      'opensAt': opensAt,
      'closesAt': closesAt,
    };
  }
}

Map<int, OpeningHoursData> defaultServiceOpeningHours() {
  return {
    for (var weekday = 1; weekday <= 7; weekday++)
      weekday: OpeningHoursData(
        isOpen: weekday <= DateTime.friday,
        opensAt: '08:00',
        closesAt: '20:00',
      ),
  };
}

Map<int, OpeningHoursData> openingHoursFromFirebase(Object? value) {
  final data = mapFromFirebase(value);
  final openingHours = <int, OpeningHoursData>{};

  for (final entry in data.entries) {
    final weekday = int.tryParse(entry.key);
    if (weekday == null ||
        weekday < DateTime.monday ||
        weekday > DateTime.sunday) {
      continue;
    }

    openingHours[weekday] = OpeningHoursData.fromFirebase(entry.value);
  }

  return openingHours;
}

Map<String, Object?> openingHoursToFirebase(
  Map<int, OpeningHoursData> openingHours,
) {
  return {
    for (final entry in openingHours.entries)
      '${entry.key}': entry.value.toFirebase(),
  };
}

int? minutesFromClockText(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

String clockTextFromTimeOfDay(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const spotCategoryIconAssets = {
  'Stance': 'assets/spot_icons/stance.png',
  'Drift': 'assets/spot_icons/drift.png',
  'Photo': 'assets/spot_icons/photo.png',
  'Meet': 'assets/spot_icons/meet.png',
  'Drive': 'assets/spot_icons/drive.png',
  'Service': 'assets/spot_icons/service.png',
  'Detailing': 'assets/spot_icons/detailing.png',
  'Wash': 'assets/spot_icons/wash.png',
  'Store': 'assets/spot_icons/store.png',
  'Drag': 'assets/spot_icons/drag.png',
  'Food': 'assets/spot_icons/food.png',
};

const spotCategoryColors = {
  'Stance': Color(0xFFFF1B72),
  'Drift': Color(0xFFFF7A00),
  'Photo': Color(0xFF9B35FF),
  'Meet': Color(0xFF8AE600),
  'Drive': Color(0xFF00B8FF),
  'Service': Color(0xFFFFD400),
  'Detailing': Color(0xFF00E0C7),
  'Wash': Color(0xFF008CFF),
  'Store': Color(0xFFA83DFF),
  'Drag': Color(0xFFFF1635),
  'Food': Color(0xFFFF1B8D),
};

const regularUserCarIconAsset = 'assets/user_cars/car_blue.png';
const verifiedUserCarIconAsset = 'assets/user_cars/car_green.png';
const friendUserCarIconAsset = 'assets/user_cars/car_purple.png';

String spotIconAssetPathForCategory(String category) {
  return spotCategoryIconAssets[category] ?? spotCategoryIconAssets['Photo']!;
}

String primarySpotCategory(CarSpot spot) {
  for (final category in spot.categories) {
    if (spotCategoryIconAssets.containsKey(category)) {
      return category;
    }
  }

  return 'Photo';
}

String spotIconAssetPathForSpot(CarSpot spot) {
  return spotIconAssetPathForCategory(primarySpotCategory(spot));
}

Color spotColorForCategory(String category) {
  return spotCategoryColors[category] ?? blue;
}

Color spotColorForSpot(CarSpot spot) {
  return spotColorForCategory(primarySpotCategory(spot));
}

final submittedSpots = ValueNotifier<List<CarSpot>>([]);
final savedSpots = ValueNotifier<List<CarSpot>>([]);
final reviewSpots = ValueNotifier<List<CarSpot>>([]);
final userSettings = ValueNotifier<UserSettingsData>(defaultUserSettings());
final garageCars = ValueNotifier<List<GarageCar>>(defaultGarageCars());

enum PhotoCropShape { rectangle, circle }

Future<String?> pickPhotoFromPhone(
  BuildContext context, {
  double cropAspectRatio = 1,
  PhotoCropShape cropShape = PhotoCropShape.rectangle,
}) async {
  try {
    final path = await photoPickerChannel.invokeMethod<String>('pickPhoto');

    if (!context.mounted || path == null || path.trim().isEmpty) {
      return path;
    }

    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(
          sourcePath: path,
          cropAspectRatio: cropAspectRatio,
          cropShape: cropShape,
        ),
      ),
    );
  } on PlatformException catch (error) {
    if (!context.mounted) {
      return null;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          error.message ?? 'Could not open photo picker.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return null;
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Photo picker is not connected in Android native code.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open photo picker. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return null;
  }
}

class PhotoCropScreen extends StatefulWidget {
  final String sourcePath;
  final double cropAspectRatio;
  final PhotoCropShape cropShape;

  const PhotoCropScreen({
    super.key,
    required this.sourcePath,
    required this.cropAspectRatio,
    this.cropShape = PhotoCropShape.rectangle,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  double zoom = 1;
  Offset offset = Offset.zero;
  double editorWidth = 0;
  double editorHeight = 0;
  double cropWidth = 0;
  double cropHeight = 0;
  double gestureStartZoom = 1;
  int? imageWidth;
  int? imageHeight;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadImageSize();
  }

  Future<void> loadImageSize() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      final normalized = decoded == null ? null : img.bakeOrientation(decoded);

      if (!mounted || normalized == null) {
        return;
      }

      setState(() {
        imageWidth = normalized.width;
        imageHeight = normalized.height;
      });
    } catch (_) {}
  }

  double minZoomForLayout() {
    final width = imageWidth;
    final height = imageHeight;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return 1;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    return math.max(
      1.0,
      math.max(
        cropWidth / (width * baseScale),
        cropHeight / (height * baseScale),
      ),
    );
  }

  Offset clampedOffset(Offset value, {double? zoomValue}) {
    final width = imageWidth;
    final height = imageHeight;
    final currentZoom = zoomValue ?? zoom;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return value;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    final displayWidth = width * baseScale * currentZoom;
    final displayHeight = height * baseScale * currentZoom;
    final cropLeft = (editorWidth - cropWidth) / 2;
    final cropTop = (editorHeight - cropHeight) / 2;
    final cropRight = cropLeft + cropWidth;
    final cropBottom = cropTop + cropHeight;
    final minX = cropRight - (editorWidth + displayWidth) / 2;
    final maxX = cropLeft - (editorWidth - displayWidth) / 2;
    final minY = cropBottom - (editorHeight + displayHeight) / 2;
    final maxY = cropTop - (editorHeight - displayHeight) / 2;

    return Offset(
      value.dx.clamp(minX, maxX).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Future<void> saveCroppedPhoto() async {
    if (isSaving) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final file = File(widget.sourcePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('Could not read selected image.');
      }

      final normalized = img.bakeOrientation(decoded);
      final width = normalized.width;
      final height = normalized.height;
      final hasLayout = editorWidth > 0 &&
          editorHeight > 0 &&
          cropWidth > 0 &&
          cropHeight > 0;
      final fallbackWidth = math.min(width, height);
      final fallbackHeight = math.min(width, height);
      final baseScale = hasLayout
          ? math.min(editorWidth / width, editorHeight / height)
          : 1.0;
      final effectiveZoom = math.max(zoom, minZoomForLayout());
      final totalScale = hasLayout ? baseScale * effectiveZoom : 1.0;
      final cropPixelWidth = (hasLayout ? cropWidth / totalScale : fallbackWidth)
          .round()
          .clamp(1, width)
          .toInt();
      final cropPixelHeight =
          (hasLayout ? cropHeight / totalScale : fallbackHeight)
          .round()
          .clamp(1, height)
          .toInt();
      final cropLeft = hasLayout ? (editorWidth - cropWidth) / 2 : 0.0;
      final cropTop = hasLayout ? (editorHeight - cropHeight) / 2 : 0.0;
      final imageLeft = hasLayout
          ? (editorWidth - width * totalScale) / 2 + offset.dx
          : (width - cropPixelWidth) / 2;
      final imageTop = hasLayout
          ? (editorHeight - height * totalScale) / 2 + offset.dy
          : (height - cropPixelHeight) / 2;
      final cropX = hasLayout
          ? ((cropLeft - imageLeft) / totalScale)
                .round()
                .clamp(0, width - cropPixelWidth)
                .toInt()
          : ((width - cropPixelWidth) / 2).round();
      final cropY = hasLayout
          ? ((cropTop - imageTop) / totalScale)
                .round()
                .clamp(0, height - cropPixelHeight)
                .toInt()
          : ((height - cropPixelHeight) / 2).round();
      final cropped = img.copyCrop(
        normalized,
        x: cropX,
        y: cropY,
        width: cropPixelWidth,
        height: cropPixelHeight,
      );
      final directory = await Directory.systemTemp.createTemp('ccs_photo_');
      final croppedPath =
          '${directory.path}${Platform.pathSeparator}photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File(croppedPath);

      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 92));

      if (mounted) {
        Navigator.pop(context, croppedFile.path);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not prepare photo: $error',
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Adjust Photo'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Use photo',
            onPressed: isSaving ? null : saveCroppedPhoto,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          editorWidth = (constraints.maxWidth - 40).clamp(260, 520).toDouble();
          editorHeight = math
              .min(constraints.maxHeight * 0.58, 560)
              .clamp(330, 560)
              .toDouble();
          final frameMaxWidth = editorWidth - 34;
          final frameMaxHeight = editorHeight - 70;
          final isCircleCrop = widget.cropShape == PhotoCropShape.circle;
          cropWidth = frameMaxWidth;
          final cropRatio = isCircleCrop
              ? 1.0
              : widget.cropAspectRatio <= 0
              ? 1.0
              : widget.cropAspectRatio;
          cropHeight = cropWidth / cropRatio;
          if (cropHeight > frameMaxHeight) {
            cropHeight = frameMaxHeight;
            cropWidth = cropHeight * cropRatio;
          }
          final minZoom = minZoomForLayout();
          final maxZoom = math.max(3.0, minZoom * 3);
          final effectiveZoom = zoom.clamp(minZoom, maxZoom).toDouble();
          if ((zoom - effectiveZoom).abs() > 0.001) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  zoom = effectiveZoom;
                  offset = clampedOffset(offset, zoomValue: effectiveZoom);
                });
              }
            });
          }
          offset = clampedOffset(offset, zoomValue: effectiveZoom);
          final cropLeft = (editorWidth - cropWidth) / 2;
          final cropTop = (editorHeight - cropHeight) / 2;
          final cropRightWidth = editorWidth - cropLeft - cropWidth;
          final cropBottomHeight = editorHeight - cropTop - cropHeight;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Center(
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) {
                    gestureStartZoom = effectiveZoom;
                  },
                  onScaleUpdate: (details) {
                    final nextZoom = (gestureStartZoom * details.scale)
                        .clamp(minZoom, maxZoom)
                        .toDouble();
                    setState(() {
                      zoom = nextZoom;
                      offset = clampedOffset(
                        offset + details.focalPointDelta,
                        zoomValue: nextZoom,
                      );
                    });
                  },
                  child: Container(
                    width: editorWidth,
                    height: editorHeight,
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.translate(
                          offset: offset,
                          child: Transform.scale(
                            scale: effectiveZoom,
                            child: Image.file(
                              File(widget.sourcePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white38,
                                  size: 44,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          right: 0,
                          height: cropTop,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: cropTop,
                          width: cropLeft,
                          height: cropHeight,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: cropTop,
                          width: cropRightWidth,
                          height: cropHeight,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: cropBottomHeight,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          left: cropLeft,
                          top: cropTop,
                          child: IgnorePointer(
                            child: Container(
                              width: cropWidth,
                              height: cropHeight,
                              decoration: BoxDecoration(
                                shape: isCircleCrop
                                    ? BoxShape.circle
                                    : BoxShape.rectangle,
                                borderRadius: isCircleCrop
                                    ? null
                                    : BorderRadius.circular(12),
                                border: Border.all(color: blue, width: 2),
                              ),
                              child: isCircleCrop
                                  ? const SizedBox.shrink()
                                  : Stack(
                                      children: [
                                        Center(
                                          child: Container(
                                            width: cropWidth,
                                            height: 1,
                                            color: Colors.white.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                        ),
                                        Center(
                                          child: Container(
                                            width: 1,
                                            height: cropHeight,
                                            color: Colors.white.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        if (isCircleCrop)
                          Positioned(
                            left: cropLeft,
                            top: cropTop,
                            child: IgnorePointer(
                              child: Container(
                                width: cropWidth,
                                height: cropHeight,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.36,
                                      ),
                                      blurRadius: 18,
                                      spreadRadius: -6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_out, color: Colors.white54),
                    Expanded(
                      child: Slider(
                        value: effectiveZoom,
                        min: minZoom,
                        max: maxZoom,
                        activeColor: blue,
                        inactiveColor: Colors.white24,
                        onChanged: (value) {
                          setState(() {
                            zoom = value;
                            offset = clampedOffset(offset, zoomValue: value);
                          });
                        },
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Colors.white54),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : saveCroppedPhoto,
                  icon: const Icon(Icons.check),
                  label: Text(isSaving ? 'Saving...' : 'Use Photo'),
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
        },
      ),
    );
  }
}

enum UserRole { admin, user }

enum SpotStatus { pending, approved, rejected }

class AppUser {
  final String uid;
  final String name;
  final String username;
  final String email;
  final String? photoUrl;
  final String bio;
  final String? avatarPath;
  final UserRole role;
  final bool verified;
  final String city;
  final String country;

  const AppUser({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    this.photoUrl,
    this.bio = 'Find. Drive. Shoot.',
    this.avatarPath,
    required this.role,
    this.verified = false,
    required this.city,
    required this.country,
  });
}

// Fallback user for preview/testing before a Firebase login happens.
AppUser currentUser = const AppUser(
  uid: 'mock_user',
  name: 'Aleksej',
  username: 'pasegorov8',
  email: '',
  role: UserRole.admin,
  verified: true,
  city: 'Riga',
  country: 'Latvia',
);

String roleName(UserRole role) {
  return role == UserRole.admin ? 'admin' : 'user';
}

UserRole roleFromFirebase(Object? value) {
  return value == 'admin' ? UserRole.admin : UserRole.user;
}

Future<bool> loadRememberMePreference() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(rememberMeKey) ?? true;
}

Future<void> saveRememberMePreference(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(rememberMeKey, value);
  rememberMeEnabled = value;
}

Future<void> signOutCurrentAccount() async {
  await saveRememberMePreference(false);
  await spotSyncSubscription?.cancel();
  spotSyncSubscription = null;

  await FirebaseAuth.instance.signOut();
  await GoogleSignIn.instance.signOut();

  currentUser = const AppUser(
    uid: 'mock_user',
    name: 'Aleksej',
    username: 'pasegorov8',
    email: '',
    role: UserRole.admin,
    verified: true,
    city: 'Riga',
    country: 'Latvia',
  );

  reviewSpots.value = [];
  submittedSpots.value = [];
  savedSpots.value = [];
  userSettings.value = defaultUserSettings();
  garageCars.value = defaultGarageCars();
}

String spotStatusName(SpotStatus status) {
  switch (status) {
    case SpotStatus.pending:
      return 'pending';
    case SpotStatus.approved:
      return 'approved';
    case SpotStatus.rejected:
      return 'rejected';
  }
}

SpotStatus spotStatusFromFirebase(Object? value) {
  switch (value) {
    case 'approved':
      return SpotStatus.approved;
    case 'rejected':
      return SpotStatus.rejected;
    default:
      return SpotStatus.pending;
  }
}

String cleanProfileUsername(String value) {
  return value
      .trim()
      .replaceAll('@', '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String usernameKey(String value) {
  return cleanProfileUsername(value).toLowerCase();
}

String makeUsernameFromFirebaseUser(User user) {
  final displayName = user.displayName?.trim();
  final emailName = user.email?.split('@').first.trim();
  final rawName = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : (emailName != null && emailName.isNotEmpty)
      ? emailName
      : 'ccs_driver';
  final cleanName = cleanProfileUsername(rawName);

  return cleanName.isEmpty ? 'ccs_driver' : cleanName;
}

String providerNameForFirebaseUser(User user) {
  if (user.isAnonymous) {
    return 'telegram';
  }

  final providerIds = user.providerData.map((provider) => provider.providerId);
  if (providerIds.contains('google.com')) {
    return 'google';
  }

  return providerIds.isEmpty ? 'firebase' : providerIds.first;
}

CollectionReference<Map<String, dynamic>> usernamesCollection() {
  return FirebaseFirestore.instance.collection('usernames');
}

enum UsernameAvailability {
  unchanged,
  checking,
  available,
  taken,
  invalid,
  error,
}

Future<UsernameAvailability> checkUsernameAvailabilityForCurrentUser(
  String username, {
  required String currentUsername,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanUsername = cleanProfileUsername(username);

  if (cleanUsername.length < 3) {
    return UsernameAvailability.invalid;
  }

  if (usernameKey(cleanUsername) == usernameKey(currentUsername)) {
    return UsernameAvailability.unchanged;
  }

  if (firebaseUser == null) {
    return UsernameAvailability.error;
  }

  try {
    final snapshot = await usernamesCollection()
        .doc(usernameKey(cleanUsername))
        .get();

    if (!snapshot.exists) {
      return UsernameAvailability.available;
    }

    final ownerUid = snapshot.data()?['uid'] as String?;
    return ownerUid == firebaseUser.uid
        ? UsernameAvailability.unchanged
        : UsernameAvailability.taken;
  } catch (_) {
    return UsernameAvailability.error;
  }
}

String usernameAvailabilityText(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.unchanged:
      return 'This is your current nickname.';
    case UsernameAvailability.checking:
      return 'Checking nickname availability...';
    case UsernameAvailability.available:
      return 'Nickname is available.';
    case UsernameAvailability.taken:
      return 'This nickname is already taken.';
    case UsernameAvailability.invalid:
      return 'Nickname must be at least 3 characters.';
    case UsernameAvailability.error:
      return 'Could not check nickname availability.';
  }
}

Color usernameAvailabilityColor(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Colors.greenAccent;
    case UsernameAvailability.checking:
      return Colors.white54;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Colors.redAccent;
  }
}

IconData usernameAvailabilityIcon(UsernameAvailability availability) {
  switch (availability) {
    case UsernameAvailability.available:
    case UsernameAvailability.unchanged:
      return Icons.check_circle_outline;
    case UsernameAvailability.checking:
      return Icons.hourglass_empty;
    case UsernameAvailability.taken:
    case UsernameAvailability.invalid:
    case UsernameAvailability.error:
      return Icons.error_outline;
  }
}

String fallbackUsernameSuffix(String uid) {
  return uid.length <= 6 ? uid : uid.substring(0, 6);
}

Future<String> reserveUsernameForCurrentUser({
  required String preferredUsername,
  String? previousUsername,
  bool allowFallback = false,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before changing your nickname.',
    );
  }

  final cleanPreferred = cleanProfileUsername(preferredUsername);

  if (cleanPreferred.length < 3) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'username-too-short',
      message: 'Nickname must be at least 3 characters.',
    );
  }

  final suffix = fallbackUsernameSuffix(firebaseUser.uid);

  for (var attempt = 0; attempt < 20; attempt++) {
    final candidate = attempt == 0
        ? cleanPreferred
        : attempt == 1
        ? '${cleanPreferred}_$suffix'
        : '${cleanPreferred}_${suffix}_$attempt';
    final key = usernameKey(candidate);
    final usernameRef = usernamesCollection().doc(key);
    final previousKey = previousUsername == null
        ? ''
        : usernameKey(previousUsername);
    final previousRef = previousKey.isEmpty || previousKey == key
        ? null
        : usernamesCollection().doc(previousKey);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(usernameRef);
        final previousSnapshot = previousRef == null
            ? null
            : await transaction.get(previousRef);
        final existingUid = snapshot.data()?['uid'] as String?;
        final previousUid = previousSnapshot?.data()?['uid'] as String?;

        if (snapshot.exists && existingUid != firebaseUser.uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'username-taken',
            message: 'This nickname is already taken.',
          );
        }

        transaction.set(usernameRef, {
          'uid': firebaseUser.uid,
          'username': candidate,
          'usernameKey': key,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (previousSnapshot != null &&
            previousSnapshot.exists &&
            previousUid == firebaseUser.uid) {
          transaction.delete(previousRef!);
        }
      });

      return candidate;
    } on FirebaseException catch (error) {
      if (!allowFallback || error.code != 'username-taken') {
        rethrow;
      }
    }
  }

  throw FirebaseException(
    plugin: 'cloud_firestore',
    code: 'username-taken',
    message: 'This nickname is already taken.',
  );
}

Future<UserRole> defaultRoleForNewFirebaseUser() async {
  try {
    final existingUsers = await FirebaseFirestore.instance
        .collection('users')
        .limit(1)
        .get();

    // First account in a fresh Firebase project becomes admin for the prototype.
    return existingUsers.docs.isEmpty ? UserRole.admin : UserRole.user;
  } catch (_) {
    return UserRole.user;
  }
}

Future<AppUser?> loadCurrentFirebaseUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return null;
  }

  try {
    currentUser = await saveFirebaseUser(
      firebaseUser,
      provider: providerNameForFirebaseUser(firebaseUser),
    );
    return currentUser;
  } catch (_) {
    return null;
  }
}

Future<AppUser> saveFirebaseUser(
  User firebaseUser, {
  required String provider,
  String? displayNameOverride,
  String? usernameOverride,
  String? emailOverride,
  String? photoUrlOverride,
  String? telegramUsername,
}) async {
  final userRef = FirebaseFirestore.instance
      .collection('users')
      .doc(firebaseUser.uid);
  final snapshot = await userRef.get();
  final data = snapshot.data();
  final isNewUser = !snapshot.exists;

  if (!isNewUser && userBanIsActive(data)) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'user-banned',
      message: 'This account is banned.',
    );
  }

  if (!isNewUser && data?['deleted'] == true) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'user-deleted',
      message: 'This account was removed.',
    );
  }

  final role = isNewUser
      ? await defaultRoleForNewFirebaseUser()
      : roleFromFirebase(data?['role']);
  final name = (data?['name'] as String?)?.trim().isNotEmpty == true
      ? data!['name'] as String
      : displayNameOverride?.trim().isNotEmpty == true
      ? displayNameOverride!.trim()
      : firebaseUser.displayName ?? 'CCS Driver';
  final rawUsername = (data?['username'] as String?)?.trim().isNotEmpty == true
      ? data!['username'] as String
      : usernameOverride?.trim().isNotEmpty == true
      ? usernameOverride!.trim()
      : makeUsernameFromFirebaseUser(firebaseUser);
  final username = await reserveUsernameForCurrentUser(
    preferredUsername: rawUsername,
    previousUsername: data?['username'] as String?,
    allowFallback: true,
  );
  final city = (data?['city'] as String?)?.trim().isNotEmpty == true
      ? data!['city'] as String
      : 'Riga';
  final country = (data?['country'] as String?)?.trim().isNotEmpty == true
      ? data!['country'] as String
      : 'Latvia';
  final photoUrl = (data?['photoUrl'] as String?)?.trim().isNotEmpty == true
      ? data!['photoUrl'] as String
      : photoUrlOverride ?? firebaseUser.photoURL;
  final bio = (data?['bio'] as String?)?.trim().isNotEmpty == true
      ? data!['bio'] as String
      : 'Night drive setup, Riga spots, clean reels, and low car routes.';
  final avatarPath = (data?['avatarPath'] as String?)?.trim().isNotEmpty == true
      ? data!['avatarPath'] as String
      : null;
  final verified = role == UserRole.admin || data?['verified'] == true;
  final settings = UserSettingsData.fromFirebase(data?['settings']);
  final garage = garageCarsFromFirebase(data?['garage']);

  userSettings.value = settings;
  garageCars.value = garage;

  final firebaseData = <String, Object?>{
    'uid': firebaseUser.uid,
    'name': name,
    'username': username,
    'usernameKey': usernameKey(username),
    'email': emailOverride ?? firebaseUser.email ?? '',
    'photoUrl': photoUrl,
    'bio': bio,
    'avatarPath': avatarPath,
    'role': roleName(role),
    'verified': verified,
    'city': city,
    'country': country,
    'settings': settings.toFirebase(),
    'garage': garage.map((car) => car.toFirebase()).toList(),
    'provider': provider,
    'telegramUsername': telegramUsername,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (isNewUser) {
    firebaseData['createdAt'] = FieldValue.serverTimestamp();
  }

  await userRef.set(firebaseData, SetOptions(merge: true));

  return AppUser(
    uid: firebaseUser.uid,
    name: name,
    username: username,
    email: emailOverride ?? firebaseUser.email ?? '',
    photoUrl: photoUrl,
    bio: bio,
    avatarPath: avatarPath,
    role: role,
    verified: verified,
    city: city,
    country: country,
  );
}

Future<AppUser> signInWithTelegramAndSaveUser() async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check setup first.',
    );
  }

  final baseUrl = telegramAuthBaseUrl.trim();
  if (baseUrl.contains('YOUR_CCS_TELEGRAM_AUTH_BACKEND')) {
    throw Exception(
      'Telegram backend URL is not set. Deploy telegram_auth_server first.',
    );
  }

  final startData = await getJsonFromUrl('$baseUrl/api/telegram-start');
  final sessionId = stringFromFirebase(startData['sessionId'], '');
  final loginUrl = stringFromFirebase(startData['loginUrl'], '');

  if (sessionId.isEmpty || loginUrl.isEmpty) {
    throw Exception('Telegram backend returned an invalid login session.');
  }

  final opened = await launchUrl(
    Uri.parse(loginUrl),
    mode: LaunchMode.externalApplication,
  );

  if (!opened) {
    throw Exception('Could not open Telegram login page.');
  }

  Map<String, dynamic>? completeData;

  for (var attempt = 0; attempt < 90; attempt++) {
    await Future.delayed(const Duration(seconds: 2));

    final statusData = await getJsonFromUrl(
      '$baseUrl/api/telegram-status?sessionId=${Uri.encodeComponent(sessionId)}',
    );
    final status = stringFromFirebase(statusData['status'], 'pending');

    if (status == 'complete') {
      completeData = statusData;
      break;
    }

    if (status == 'error') {
      throw Exception(
        stringFromFirebase(statusData['message'], 'Telegram login failed.'),
      );
    }
  }

  if (completeData == null) {
    throw Exception('Telegram login timed out. Try again.');
  }

  final firebaseToken = stringFromFirebase(completeData['firebaseToken'], '');
  final telegramData = mapFromFirebase(completeData['telegram']);

  if (firebaseToken.isEmpty) {
    throw Exception('Telegram backend did not return a Firebase token.');
  }

  final userCredential = await FirebaseAuth.instance.signInWithCustomToken(
    firebaseToken,
  );
  final firebaseUser = userCredential.user;

  if (firebaseUser == null) {
    throw Exception('Firebase login finished without a user.');
  }

  final telegramUsername = stringFromFirebase(telegramData['username'], '');
  final firstName = stringFromFirebase(telegramData['first_name'], '');
  final lastName = stringFromFirebase(telegramData['last_name'], '');
  final fullName = ('$firstName $lastName').trim();
  final telegramId = stringFromFirebase(telegramData['id'], firebaseUser.uid);
  final photoUrl = stringFromFirebase(telegramData['photo_url'], '');
  final fallbackUsername = telegramUsername.isNotEmpty
      ? telegramUsername
      : 'telegram_$telegramId';

  currentUser = await saveFirebaseUser(
    firebaseUser,
    provider: 'telegram',
    displayNameOverride: fullName.isEmpty ? '@$fallbackUsername' : fullName,
    usernameOverride: fallbackUsername,
    emailOverride: '',
    photoUrlOverride: photoUrl.isEmpty ? null : photoUrl,
    telegramUsername: fallbackUsername,
  );
  startFirebaseSpotSync();
  return currentUser;
}

Future<Map<String, dynamic>> getJsonFromUrl(String url) async {
  final client = HttpClient();

  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed ${response.statusCode}: $body');
    }

    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Backend returned invalid JSON.');
  } finally {
    client.close(force: true);
  }
}

bool isNetworkUrl(String? value) {
  final cleanValue = value?.trim() ?? '';
  return cleanValue.startsWith('http://') || cleanValue.startsWith('https://');
}

String imageContentTypeForPath(String path) {
  // R2 uploads are normalized to compressed JPEGs to keep storage and bandwidth low.
  return 'image/jpeg';
}

String imageExtensionForPath(String path) {
  // Keep all uploaded images as JPG, even if the original phone image was PNG/WEBP.
  return 'jpg';
}


String safeR2Path(String value) {
  final clean = value
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+'), '/');

  return clean.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_');
}

Future<List<int>> compressedJpegBytesFromFile(
  String localPhotoPath, {
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final file = File(localPhotoPath);

  if (!await file.exists()) {
    throw Exception('Selected image file was not found on this phone.');
  }

  final originalBytes = await file.readAsBytes();
  final decoded = img.decodeImage(originalBytes);

  if (decoded == null) {
    throw Exception('Could not read selected image. Try another photo.');
  }

  var normalized = img.bakeOrientation(decoded);
  final longestSide = math.max(normalized.width, normalized.height);

  if (longestSide > maxLongSide) {
    final scale = maxLongSide / longestSide;
    normalized = img.copyResize(
      normalized,
      width: math.max(1, (normalized.width * scale).round()),
      height: math.max(1, (normalized.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  return img.encodeJpg(normalized, quality: quality);
}

Future<Map<String, dynamic>> postJsonToUrl(
  String url,
  Map<String, Object?> body,
) async {
  final client = HttpClient();

  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Backend returned invalid JSON.');
  } finally {
    client.close(force: true);
  }
}

Future<void> putBytesToPresignedUrl({
  required String uploadUrl,
  required List<int> bytes,
  required String contentType,
}) async {
  final client = HttpClient();

  try {
    final request = await client.putUrl(Uri.parse(uploadUrl));
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    request.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('R2 upload failed ${response.statusCode}: $responseBody');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> uploadImageBytesToR2({
  required String r2Path,
  required List<int> bytes,
  String contentType = 'image/jpeg',
}) async {
  final presignData = await postJsonToUrl(r2PresignUploadUrl, {
    'path': safeR2Path(r2Path),
    'contentType': contentType,
  });

  final uploadUrl = stringFromFirebase(presignData['uploadUrl'], '');
  final publicUrl = stringFromFirebase(presignData['publicUrl'], '');

  if (uploadUrl.isEmpty || publicUrl.isEmpty) {
    throw Exception('R2 backend did not return upload URL.');
  }

  await putBytesToPresignedUrl(
    uploadUrl: uploadUrl,
    bytes: bytes,
    contentType: contentType,
  );

  return publicUrl;
}

Future<String> uploadImageToR2({
  required String r2Path,
  required String localPhotoPath,
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final bytes = await compressedJpegBytesFromFile(
    localPhotoPath,
    maxLongSide: maxLongSide,
    quality: quality,
  );

  return uploadImageBytesToR2(
    r2Path: r2Path,
    bytes: bytes,
    contentType: 'image/jpeg',
  );
}

Future<AppUser> signInWithGoogleAndSaveUser() async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check google-services.json and Android setup.',
    );
  }

  if (googleSignInSetupError != null) {
    throw Exception(googleSignInSetupError);
  }

  if (!GoogleSignIn.instance.supportsAuthenticate()) {
    throw Exception('Google Sign-In is not supported on this platform.');
  }

  final googleUser = await GoogleSignIn.instance.authenticate();
  final googleAuth = googleUser.authentication;
  final idToken = googleAuth.idToken;

  if (idToken == null) {
    throw Exception('Google did not return an ID token.');
  }

  final credential = GoogleAuthProvider.credential(idToken: idToken);
  final userCredential = await FirebaseAuth.instance.signInWithCredential(
    credential,
  );
  final firebaseUser = userCredential.user;

  if (firebaseUser == null) {
    throw Exception('Firebase login finished without a user.');
  }

  currentUser = await saveFirebaseUser(firebaseUser, provider: 'google');
  startFirebaseSpotSync();
  return currentUser;
}

class UserSettingsData {
  final String instagram;
  final String tiktok;
  final String telegram;
  final bool reviewNotifications;
  final bool likeNotifications;
  final bool commentNotifications;
  final bool newSpotNotifications;
  final bool newMessageNotifications;
  final bool publicProfile;
  final bool showSavedSpots;
  final bool showGarage;

  const UserSettingsData({
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    required this.reviewNotifications,
    required this.likeNotifications,
    required this.commentNotifications,
    required this.newSpotNotifications,
    this.newMessageNotifications = true,
    required this.publicProfile,
    required this.showSavedSpots,
    required this.showGarage,
  });

  factory UserSettingsData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);
    final defaults = defaultUserSettings();

    return UserSettingsData(
      instagram: stringFromFirebase(data['instagram'], defaults.instagram),
      tiktok: stringFromFirebase(data['tiktok'], defaults.tiktok),
      telegram: stringFromFirebase(data['telegram'], defaults.telegram),
      reviewNotifications: boolFromFirebase(
        data['reviewNotifications'],
        defaults.reviewNotifications,
      ),
      likeNotifications: boolFromFirebase(
        data['likeNotifications'],
        defaults.likeNotifications,
      ),
      commentNotifications: boolFromFirebase(
        data['commentNotifications'],
        defaults.commentNotifications,
      ),
      newSpotNotifications: boolFromFirebase(
        data['newSpotNotifications'],
        defaults.newSpotNotifications,
      ),
      newMessageNotifications: boolFromFirebase(
        data['newMessageNotifications'],
        defaults.newMessageNotifications,
      ),
      publicProfile: boolFromFirebase(
        data['publicProfile'],
        defaults.publicProfile,
      ),
      showSavedSpots: boolFromFirebase(
        data['showSavedSpots'],
        defaults.showSavedSpots,
      ),
      showGarage: boolFromFirebase(data['showGarage'], defaults.showGarage),
    );
  }

  Map<String, Object?> toFirebase() {
    return {
      'instagram': instagram,
      'tiktok': tiktok,
      'telegram': telegram,
      'reviewNotifications': reviewNotifications,
      'likeNotifications': likeNotifications,
      'commentNotifications': commentNotifications,
      'newSpotNotifications': newSpotNotifications,
      'newMessageNotifications': newMessageNotifications,
      'publicProfile': publicProfile,
      'showSavedSpots': showSavedSpots,
      'showGarage': showGarage,
    };
  }

  UserSettingsData copyWith({
    String? instagram,
    String? tiktok,
    String? telegram,
    bool? reviewNotifications,
    bool? likeNotifications,
    bool? commentNotifications,
    bool? newSpotNotifications,
    bool? newMessageNotifications,
    bool? publicProfile,
    bool? showSavedSpots,
    bool? showGarage,
  }) {
    return UserSettingsData(
      instagram: instagram ?? this.instagram,
      tiktok: tiktok ?? this.tiktok,
      telegram: telegram ?? this.telegram,
      reviewNotifications: reviewNotifications ?? this.reviewNotifications,
      likeNotifications: likeNotifications ?? this.likeNotifications,
      commentNotifications: commentNotifications ?? this.commentNotifications,
      newSpotNotifications: newSpotNotifications ?? this.newSpotNotifications,
      newMessageNotifications: newMessageNotifications ?? this.newMessageNotifications,
      publicProfile: publicProfile ?? this.publicProfile,
      showSavedSpots: showSavedSpots ?? this.showSavedSpots,
      showGarage: showGarage ?? this.showGarage,
    );
  }
}


Future<void> saveCurrentUserSettings(UserSettingsData settings) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    userSettings.value = settings;
    return;
  }

  userSettings.value = settings;

  await usersCollection().doc(firebaseUser.uid).set({
    'settings': settings.toFirebase(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

UserSettingsData defaultUserSettings() {
  return const UserSettingsData(
    instagram: 'https://instagram.com/ccs.lv',
    tiktok: 'https://tiktok.com/@ccs',
    telegram: 'https://t.me/ccs_lv',
    reviewNotifications: true,
    likeNotifications: true,
    commentNotifications: false,
    newSpotNotifications: true,
    newMessageNotifications: true,
    publicProfile: true,
    showSavedSpots: false,
    showGarage: true,
  );
}

class CarSpot {
  final String id;
  final String name;
  final String cityCountry;
  final LatLng coordinates;
  final String description;
  final List<String> categories;
  final double rating;
  final String photoUrl;
  final List<String> photoUrls;
  final String? localPhotoPath;
  final String reelLink;
  final String contactPhone;
  final String contactInstagram;
  final String contactEmail;
  final Map<int, OpeningHoursData> openingHours;
  final String ownerUid;
  final String ownerUsername;
  final String bestTime;
  final String parking;
  final String roadQuality;
  final bool lowCarFriendly;
  final String policeRisk;
  final String traffic;
  final String lighting;
  final String crowd;
  final String addedBy;
  final String addedByUid;
  final SpotStatus status;
  final int createdAtMillis;
  final bool isTemporary;
  final int? startsAtMillis;
  final int? expiresAtMillis;
  final bool verifiedOnly;

  const CarSpot({
    this.id = '',
    required this.name,
    required this.cityCountry,
    required this.coordinates,
    required this.description,
    required this.categories,
    required this.rating,
    required this.photoUrl,
    this.photoUrls = const [],
    this.localPhotoPath,
    required this.reelLink,
    this.contactPhone = '',
    this.contactInstagram = '',
    this.contactEmail = '',
    this.openingHours = const {},
    this.ownerUid = '',
    this.ownerUsername = '',
    required this.bestTime,
    required this.parking,
    required this.roadQuality,
    required this.lowCarFriendly,
    required this.policeRisk,
    required this.traffic,
    required this.lighting,
    required this.crowd,
    required this.addedBy,
    this.addedByUid = '',
    required this.status,
    this.createdAtMillis = 0,
    this.isTemporary = false,
    this.startsAtMillis,
    this.expiresAtMillis,
    this.verifiedOnly = false,
  });

  CarSpot copyWith({
    String? id,
    String? name,
    String? cityCountry,
    LatLng? coordinates,
    String? description,
    List<String>? categories,
    double? rating,
    String? photoUrl,
    List<String>? photoUrls,
    String? localPhotoPath,
    String? reelLink,
    String? contactPhone,
    String? contactInstagram,
    String? contactEmail,
    Map<int, OpeningHoursData>? openingHours,
    String? ownerUid,
    String? ownerUsername,
    String? bestTime,
    String? parking,
    String? roadQuality,
    bool? lowCarFriendly,
    String? policeRisk,
    String? traffic,
    String? lighting,
    String? crowd,
    String? addedBy,
    String? addedByUid,
    SpotStatus? status,
    int? createdAtMillis,
    bool? isTemporary,
    int? startsAtMillis,
    int? expiresAtMillis,
    bool? verifiedOnly,
  }) {
    return CarSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      cityCountry: cityCountry ?? this.cityCountry,
      coordinates: coordinates ?? this.coordinates,
      description: description ?? this.description,
      categories: categories ?? this.categories,
      rating: rating ?? this.rating,
      photoUrl: photoUrl ?? this.photoUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      localPhotoPath: localPhotoPath ?? this.localPhotoPath,
      reelLink: reelLink ?? this.reelLink,
      contactPhone: contactPhone ?? this.contactPhone,
      contactInstagram: contactInstagram ?? this.contactInstagram,
      contactEmail: contactEmail ?? this.contactEmail,
      openingHours: openingHours ?? this.openingHours,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      bestTime: bestTime ?? this.bestTime,
      parking: parking ?? this.parking,
      roadQuality: roadQuality ?? this.roadQuality,
      lowCarFriendly: lowCarFriendly ?? this.lowCarFriendly,
      policeRisk: policeRisk ?? this.policeRisk,
      traffic: traffic ?? this.traffic,
      lighting: lighting ?? this.lighting,
      crowd: crowd ?? this.crowd,
      addedBy: addedBy ?? this.addedBy,
      addedByUid: addedByUid ?? this.addedByUid,
      status: status ?? this.status,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      isTemporary: isTemporary ?? this.isTemporary,
      startsAtMillis: startsAtMillis ?? this.startsAtMillis,
      expiresAtMillis: expiresAtMillis ?? this.expiresAtMillis,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
    );
  }

  bool get hasTemporaryWindow =>
      isTemporary && startsAtMillis != null && expiresAtMillis != null;

  bool get supportsContacts => categories.any(spotCategorySupportsContacts);

  bool get hasOwner => ownerUid.trim().isNotEmpty;

  bool get hasOpeningHours => openingHours.isNotEmpty;

  bool get hasContactInfo =>
      supportsContacts &&
      (contactPhone.trim().isNotEmpty ||
          contactInstagram.trim().isNotEmpty ||
          contactEmail.trim().isNotEmpty ||
          openingHours.isNotEmpty);

  bool get isExpired {
    final expiresAt = expiresAtMillis;
    return isTemporary &&
        expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  bool get isVisibleNow {
    if (!isTemporary) {
      return true;
    }

    final startsAt = startsAtMillis;
    final expiresAt = expiresAtMillis;

    if (startsAt == null || expiresAt == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= startsAt && now < expiresAt;
  }

  String get temporaryTimeLabel {
    if (!hasTemporaryWindow) {
      return '';
    }

    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMillis!);
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMillis!);
    return '${formatShortDateTime(startsAt)} - ${formatShortDateTime(expiresAt)}';
  }

  factory CarSpot.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final geoPoint = data['coordinates'];
    final coordinates = geoPoint is GeoPoint
        ? LatLng(geoPoint.latitude, geoPoint.longitude)
        : LatLng(
            doubleFromFirebase(data['lat'], 56.9496),
            doubleFromFirebase(data['lng'], 24.1052),
          );

    return CarSpot(
      id: doc.id,
      name: stringFromFirebase(data['name'], 'Untitled spot'),
      cityCountry: stringFromFirebase(data['cityCountry'], 'Riga, Latvia'),
      coordinates: coordinates,
      description: stringFromFirebase(
        data['description'],
        'Submitted community car spot.',
      ),
      categories: stringListFromFirebase(data['categories'], const ['Photo']),
      rating: doubleFromFirebase(data['rating'], 0),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      photoUrls: stringListFromFirebase(data['photoUrls'], const []),
      reelLink: stringFromFirebase(data['reelLink'], ''),
      contactPhone: stringFromFirebase(data['contactPhone'], ''),
      contactInstagram: stringFromFirebase(data['contactInstagram'], ''),
      contactEmail: stringFromFirebase(data['contactEmail'], ''),
      openingHours: openingHoursFromFirebase(data['openingHours']),
      ownerUid: stringFromFirebase(data['ownerUid'], ''),
      ownerUsername: stringFromFirebase(data['ownerUsername'], ''),
      bestTime: stringFromFirebase(data['bestTime'], 'Not reviewed'),
      parking: stringFromFirebase(data['parking'], 'Not reviewed'),
      roadQuality: stringFromFirebase(data['roadQuality'], 'Not reviewed'),
      lowCarFriendly: data['lowCarFriendly'] == true,
      policeRisk: stringFromFirebase(data['policeRisk'], 'Not reviewed'),
      traffic: stringFromFirebase(data['traffic'], 'Not reviewed'),
      lighting: stringFromFirebase(data['lighting'], 'Not reviewed'),
      crowd: stringFromFirebase(data['crowd'], 'Not reviewed'),
      addedBy: stringFromFirebase(data['addedBy'], 'ccs_driver'),
      addedByUid: stringFromFirebase(data['addedByUid'], ''),
      status: spotStatusFromFirebase(data['status']),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      isTemporary: data['isTemporary'] == true,
      startsAtMillis: nullableTimestampMillisFromFirebase(data['startsAt']),
      expiresAtMillis: nullableTimestampMillisFromFirebase(data['expiresAt']),
      verifiedOnly: data['verifiedOnly'] == true,
    );
  }
}

String stringFromFirebase(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return fallback;
}

double doubleFromFirebase(Object? value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }

  return fallback;
}

int timestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return 0;
}

int? nullableTimestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return null;
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatShortDateTime(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String formatShortDate(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}';
}

List<String> stringListFromFirebase(Object? value, List<String> fallback) {
  if (value is List) {
    final list = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (list.isNotEmpty) {
      return list;
    }
  }

  return fallback;
}

bool boolFromFirebase(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

Map<String, dynamic> mapFromFirebase(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return <String, dynamic>{};
}

bool userBanIsActive(Map<String, dynamic>? data) {
  if (data?['banned'] != true) {
    return false;
  }

  final untilMillis = nullableTimestampMillisFromFirebase(data?['bannedUntil']);
  return untilMillis == null ||
      untilMillis > DateTime.now().millisecondsSinceEpoch;
}

String userBanLabel({
  required bool banned,
  required int? bannedUntilMillis,
}) {
  if (!banned) {
    return 'Active';
  }

  if (bannedUntilMillis == null) {
    return 'Banned';
  }

  if (bannedUntilMillis <= DateTime.now().millisecondsSinceEpoch) {
    return 'Ban expired';
  }

  return 'Banned until ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(bannedUntilMillis))}';
}

bool localFileExists(String? path) {
  if (path == null || path.trim().isEmpty) {
    return false;
  }

  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

CollectionReference<Map<String, dynamic>> usersCollection() {
  return FirebaseFirestore.instance.collection('users');
}

class SpotOwnerAssignment {
  final String uid;
  final String username;

  const SpotOwnerAssignment({required this.uid, required this.username});
}

Future<SpotOwnerAssignment?> findSpotOwnerAssignment(
  String rawInput, {
  SpotOwnerAssignment? currentOwner,
}) async {
  final input = rawInput.trim();

  if (input.isEmpty) {
    return null;
  }

  final cleanInput = input.startsWith('@') ? input.substring(1) : input;

  if (currentOwner != null &&
      currentOwner.uid.isNotEmpty &&
      (cleanInput == currentOwner.uid ||
          usernameKey(cleanInput) == usernameKey(currentOwner.username))) {
    return currentOwner;
  }

  final byUid = await usersCollection().doc(cleanInput).get();
  if (byUid.exists) {
    final data = byUid.data() ?? {};
    return SpotOwnerAssignment(
      uid: byUid.id,
      username: stringFromFirebase(data['username'], byUid.id),
    );
  }

  final byUsername = await usersCollection()
      .where('usernameKey', isEqualTo: usernameKey(cleanInput))
      .limit(1)
      .get();
  if (byUsername.docs.isNotEmpty) {
    final doc = byUsername.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  final byEmail = await usersCollection()
      .where('email', isEqualTo: input)
      .limit(1)
      .get();
  if (byEmail.docs.isNotEmpty) {
    final doc = byEmail.docs.first;
    final data = doc.data();
    return SpotOwnerAssignment(
      uid: doc.id,
      username: stringFromFirebase(data['username'], doc.id),
    );
  }

  return null;
}

CollectionReference<Map<String, dynamic>> liveLocationsCollection() {
  return FirebaseFirestore.instance.collection('live_locations');
}

class LiveLocationData {
  final String uid;
  final String username;
  final String name;
  final String? photoUrl;
  final UserRole role;
  final bool verified;
  final double headingDegrees;
  final LatLng coordinates;
  final int promptAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;

  const LiveLocationData({
    required this.uid,
    required this.username,
    required this.name,
    this.photoUrl,
    required this.role,
    required this.verified,
    this.headingDegrees = 0,
    required this.coordinates,
    required this.promptAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;

  factory LiveLocationData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final geoPoint = data['coordinates'];
    final coordinates = geoPoint is GeoPoint
        ? LatLng(geoPoint.latitude, geoPoint.longitude)
        : LatLng(
            doubleFromFirebase(data['lat'], 56.9496),
            doubleFromFirebase(data['lng'], 24.1052),
          );

    final role = roleFromFirebase(data['role']);

    return LiveLocationData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      role: role,
      verified: role == UserRole.admin || data['verified'] == true,
      headingDegrees: normalizedHeadingDegrees(
        doubleFromFirebase(data['heading'], 0),
      ),
      coordinates: coordinates,
      promptAtMillis: timestampMillisFromFirebase(data['promptAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }
}

CollectionReference<Map<String, dynamic>> policeReportsCollection() {
  return FirebaseFirestore.instance.collection('police_reports');
}

CollectionReference<Map<String, dynamic>> meetNotificationsCollection() {
  return FirebaseFirestore.instance.collection('meet_notifications');
}

CollectionReference<Map<String, dynamic>> adminNotificationsCollection() {
  return FirebaseFirestore.instance.collection('admin_notifications');
}

CollectionReference<Map<String, dynamic>> friendRequestsCollection() {
  return FirebaseFirestore.instance.collection('friend_requests');
}

CollectionReference<Map<String, dynamic>> friendshipsCollection() {
  return FirebaseFirestore.instance.collection('friendships');
}

CollectionReference<Map<String, dynamic>>
friendLocationNotificationsCollection() {
  return FirebaseFirestore.instance.collection('friend_location_notifications');
}

CollectionReference<Map<String, dynamic>> chatsCollection() {
  return FirebaseFirestore.instance.collection('chats');
}

CollectionReference<Map<String, dynamic>> chatMessagesCollection(String chatId) {
  return chatsCollection().doc(chatId).collection('messages');
}

String friendshipIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return '${ids[0]}_${ids[1]}';
}

String friendRequestIdFor(String fromUid, String toUid) {
  return '${fromUid}_$toUid';
}

class FriendUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final bool verified;
  final UserRole role;
  final bool banned;
  final int? bannedUntilMillis;
  final bool deleted;

  const FriendUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.verified,
    required this.role,
    required this.banned,
    this.bannedUntilMillis,
    required this.deleted,
  });

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  bool get canAppearInUserLists => !deleted && !banActive;

  factory FriendUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final role = roleFromFirebase(data['role']);
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );

    return FriendUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      role: role,
      verified: role == UserRole.admin || data['verified'] == true,
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      deleted: data['deleted'] == true,
    );
  }
}

class FriendRequestData {
  final String id;
  final String fromUid;
  final String fromUsername;
  final String fromName;
  final String toUid;
  final String toUsername;
  final String toName;
  final String status;
  final int createdAtMillis;

  const FriendRequestData({
    required this.id,
    required this.fromUid,
    required this.fromUsername,
    required this.fromName,
    required this.toUid,
    required this.toUsername,
    required this.toName,
    required this.status,
    required this.createdAtMillis,
  });

  factory FriendRequestData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return FriendRequestData(
      id: doc.id,
      fromUid: stringFromFirebase(data['fromUid'], ''),
      fromUsername: stringFromFirebase(data['fromUsername'], 'ccs_driver'),
      fromName: stringFromFirebase(data['fromName'], 'CCS Driver'),
      toUid: stringFromFirebase(data['toUid'], ''),
      toUsername: stringFromFirebase(data['toUsername'], 'ccs_driver'),
      toName: stringFromFirebase(data['toName'], 'CCS Driver'),
      status: stringFromFirebase(data['status'], 'pending'),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    );
  }
}

Future<bool> areUsersFriends(String firstUid, String secondUid) async {
  if (firstUid.trim().isEmpty || secondUid.trim().isEmpty) {
    return false;
  }

  final snapshot = await friendshipsCollection()
      .doc(friendshipIdFor(firstUid, secondUid))
      .get();
  return snapshot.exists;
}

Future<String?> pendingRequestStatusBetweenUsers(
  String firstUid,
  String secondUid,
) async {
  final outgoing = await friendRequestsCollection()
      .doc(friendRequestIdFor(firstUid, secondUid))
      .get();

  if (outgoing.exists && outgoing.data()?['status'] == 'pending') {
    return 'outgoing';
  }

  final incoming = await friendRequestsCollection()
      .doc(friendRequestIdFor(secondUid, firstUid))
      .get();

  if (incoming.exists && incoming.data()?['status'] == 'pending') {
    return 'incoming';
  }

  return null;
}

Future<void> sendFriendRequestToUser(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before adding friends.',
    );
  }

  if (user.uid == firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'cannot-add-yourself',
      message: 'You cannot add yourself as a friend.',
    );
  }

  if (await areUsersFriends(firebaseUser.uid, user.uid)) {
    return;
  }

  final incomingRef = friendRequestsCollection().doc(
    friendRequestIdFor(user.uid, firebaseUser.uid),
  );
  final incoming = await incomingRef.get();

  if (incoming.exists && incoming.data()?['status'] == 'pending') {
    await acceptFriendRequest(FriendRequestData.fromFirestore(incoming));
    return;
  }

  await friendRequestsCollection()
      .doc(friendRequestIdFor(firebaseUser.uid, user.uid))
      .set({
        'fromUid': firebaseUser.uid,
        'fromUsername': currentUser.username,
        'fromName': currentUser.name,
        'toUid': user.uid,
        'toUsername': user.username,
        'toName': user.name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

Future<void> acceptFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can accept this request.',
    );
  }

  final friendshipRef = friendshipsCollection().doc(
    friendshipIdFor(request.fromUid, request.toUid),
  );
  final requestRef = friendRequestsCollection().doc(request.id);

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    transaction.set(friendshipRef, {
      'userIds': [request.fromUid, request.toUid]..sort(),
      'users': {
        request.fromUid: {
          'uid': request.fromUid,
          'username': request.fromUsername,
          'name': request.fromName,
        },
        request.toUid: {
          'uid': request.toUid,
          'username': request.toUsername,
          'name': request.toName,
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    transaction.set(requestRef, {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

Future<void> declineFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.toUid != firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the invited user can decline this request.',
    );
  }

  await friendRequestsCollection().doc(request.id).set({
    'status': 'declined',
    'respondedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> cancelFriendRequest(FriendRequestData request) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || request.fromUid != firebaseUser.uid) {
    return;
  }

  await friendRequestsCollection().doc(request.id).delete();
}

String friendUidFromFriendshipData(
  Map<String, dynamic> data,
  String currentUid,
) {
  final userIds = stringListFromFirebase(data['userIds'], const []);

  for (final uid in userIds) {
    if (uid != currentUid) {
      return uid;
    }
  }

  return '';
}

Future<void> removeFriendship(String friendUid) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  await friendshipsCollection()
      .doc(friendshipIdFor(firebaseUser.uid, friendUid))
      .delete();
}

const double friendNearbyRadiusMeters = 5000;
const double friendAtSpotRadiusMeters = 200;
const Duration friendLocationNotificationCooldown = Duration(minutes: 30);

String friendNearbyNotificationId(String userId, String friendUid) {
  return 'nearby_${userId}_$friendUid';
}

String friendSpotNotificationId(
  String userId,
  String friendUid,
  String spotId,
) {
  return 'spot_${userId}_${friendUid}_$spotId';
}

Future<List<String>> loadCurrentFriendUids() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return const [];
  }

  final snapshot = await friendshipsCollection()
      .where('userIds', arrayContains: firebaseUser.uid)
      .get();

  return snapshot.docs
      .map((doc) => friendUidFromFriendshipData(doc.data(), firebaseUser.uid))
      .where((uid) => uid.trim().isNotEmpty)
      .toList();
}

Future<List<FriendUserData>> loadCurrentFriendUsers() async {
  final friendUids = await loadCurrentFriendUids();
  final friends = <FriendUserData>[];

  for (final uid in friendUids) {
    final snapshot = await usersCollection().doc(uid).get();
    if (snapshot.exists) {
      final user = FriendUserData.fromFirestore(snapshot);
      if (user.canAppearInUserLists) {
        friends.add(user);
      }
    }
  }

  friends.sort((a, b) => a.username.compareTo(b.username));
  return friends;
}

String directChatIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return 'direct_${ids[0]}_${ids[1]}';
}


Future<void> openMessageToUserFromContext(
  BuildContext context,
  FriendUserData user,
) async {
  try {
    final chatId = await createOrOpenDirectChat(user);
    final chat = ChatThreadData(
      id: chatId,
      isGroup: false,
      name: '',
      memberIds: [currentUser.uid, user.uid],
      memberUsernames: [currentUser.username, user.username],
      memberPhotoUrls: [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
      lastMessage: '',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    if (!context.mounted) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open chat: $error',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class ChatThreadData {
  final String id;
  final bool isGroup;
  final String name;
  final String photoUrl;
  final String description;
  final List<String> memberIds;
  final List<String> memberUsernames;
  final List<String> memberPhotoUrls;
  final String lastMessage;
  final String avatarUrl;
  final int updatedAtMillis;

  const ChatThreadData({
    required this.id,
    required this.isGroup,
    required this.name,
    this.photoUrl = '',
    this.description = '',
    required this.memberIds,
    required this.memberUsernames,
    this.memberPhotoUrls = const [],
    required this.lastMessage,
    this.avatarUrl = '',
    required this.updatedAtMillis,
  });

  factory ChatThreadData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ChatThreadData(
      id: doc.id,
      isGroup: data['isGroup'] == true,
      name: stringFromFirebase(data['name'], ''),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      description: stringFromFirebase(data['description'], ''),
      memberIds: stringListFromFirebase(data['memberIds'], const []),
      memberUsernames: stringListFromFirebase(
        data['memberUsernames'],
        const [],
      ),
      memberPhotoUrls: stringListFromFirebase(
        data['memberPhotoUrls'],
        const [],
      ),
      lastMessage: stringFromFirebase(data['lastMessage'], ''),
      avatarUrl: stringFromFirebase(data['avatarUrl'], ''),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }

  String titleForCurrentUser(String currentUid) {
    if (isGroup) {
      return name.trim().isEmpty ? 'Group chat' : name.trim();
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberUsernames.length &&
          memberUsernames[index].trim().isNotEmpty) {
        return '@${memberUsernames[index]}';
      }

      return 'Direct chat';
    }

    return 'Direct chat';
  }

  String subtitleForCurrentUser(String currentUid) {
    if (lastMessage.trim().isNotEmpty) {
      return lastMessage.trim();
    }

    if (isGroup) {
      return description.trim().isNotEmpty
          ? description.trim()
          : '${memberIds.length} members';
    }

    return 'No messages yet';
  }

  String directPhotoUrlForCurrentUser(String currentUid) {
    if (isGroup) {
      return avatarUrl;
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberPhotoUrls.length) {
        return memberPhotoUrls[index];
      }
    }

    return '';
  }
}

class ChatMessageData {
  final String id;
  final String senderUid;
  final String senderUsername;
  final String text;
  final int createdAtMillis;

  const ChatMessageData({
    required this.id,
    required this.senderUid,
    required this.senderUsername,
    required this.text,
    required this.createdAtMillis,
  });

  factory ChatMessageData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ChatMessageData(
      id: doc.id,
      senderUid: stringFromFirebase(data['senderUid'], ''),
      senderUsername: stringFromFirebase(data['senderUsername'], 'ccs_driver'),
      text: stringFromFirebase(data['text'], ''),
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    );
  }
}

Future<String> createOrOpenDirectChat(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before opening chat.',
    );
  }

  final chatId = directChatIdFor(firebaseUser.uid, user.uid);
  final memberIds = [firebaseUser.uid, user.uid];
  final memberUsernames = [currentUser.username, user.username];

  await chatsCollection().doc(chatId).set({
    'isGroup': false,
    'name': '',
    'memberIds': memberIds,
    'memberUsernames': memberUsernames,
    'memberPhotoUrls': [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
    'photoUrl': '',
    'updatedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  return chatId;
}

Future<String> createGroupChat({
  required String name,
  required List<FriendUserData> users,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before creating chat.',
    );
  }

  final uniqueUsers = <String, FriendUserData>{
    for (final user in users) user.uid: user,
  }.values.toList();
  final memberIds = [firebaseUser.uid, ...uniqueUsers.map((user) => user.uid)];
  final memberUsernames = [
    currentUser.username,
    ...uniqueUsers.map((user) => user.username),
  ];
  final fallbackName = uniqueUsers
      .map((user) => user.username)
      .where((username) => username.trim().isNotEmpty)
      .take(3)
      .join(', ');
  final doc = chatsCollection().doc();

  await doc.set({
    'isGroup': true,
    'name': name.trim().isEmpty ? fallbackName : name.trim(),
    'memberIds': memberIds,
    'memberUsernames': memberUsernames,
    'memberPhotoUrls': [currentUser.photoUrl ?? '', ...uniqueUsers.map((user) => user.photoUrl ?? '')],
    'photoUrl': '',
    'description': '',
    'lastMessage': '',
    'updatedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  return doc.id;
}

Future<void> sendChatMessage({
  required String chatId,
  required String text,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before sending messages.',
    );
  }

  final cleanText = text.trim();

  if (cleanText.isEmpty) {
    return;
  }

  await chatMessagesCollection(chatId).add({
    'senderUid': firebaseUser.uid,
    'senderUsername': currentUser.username,
    'text': cleanText,
    'createdAt': FieldValue.serverTimestamp(),
  });

  await chatsCollection().doc(chatId).set({
    'lastMessage': cleanText,
    'lastSenderUid': firebaseUser.uid,
    'lastSenderUsername': currentUser.username,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<LiveLocationData?> loadCurrentLiveLocationForUser(String uid) async {
  final snapshot = await liveLocationsCollection().doc(uid).get();

  if (!snapshot.exists) {
    return null;
  }

  final location = LiveLocationData.fromFirestore(snapshot);
  return location.isExpired ? null : location;
}

Future<bool> shouldCreateFriendLocationNotification(
  String notificationId,
) async {
  final snapshot = await friendLocationNotificationsCollection()
      .doc(notificationId)
      .get();

  if (!snapshot.exists) {
    return true;
  }

  final data = snapshot.data() ?? {};
  final lastNotifiedAtMillis = timestampMillisFromFirebase(
    data['lastNotifiedAtMillis'],
  );

  if (lastNotifiedAtMillis <= 0) {
    return true;
  }

  final elapsedMillis =
      DateTime.now().millisecondsSinceEpoch - lastNotifiedAtMillis;
  return elapsedMillis >= friendLocationNotificationCooldown.inMilliseconds;
}

Future<void> createFriendLocationNotification({
  required String notificationId,
  required String userId,
  required LiveLocationData friendLocation,
  required String type,
  required double distanceMeters,
  CarSpot? spot,
}) async {
  if (!await shouldCreateFriendLocationNotification(notificationId)) {
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  await friendLocationNotificationsCollection().doc(notificationId).set({
    'userId': userId,
    'friendUid': friendLocation.uid,
    'friendUsername': friendLocation.username,
    'friendName': friendLocation.name,
    'friendLat': friendLocation.coordinates.latitude,
    'friendLng': friendLocation.coordinates.longitude,
    'friendCoordinates': GeoPoint(
      friendLocation.coordinates.latitude,
      friendLocation.coordinates.longitude,
    ),
    'type': type,
    'distanceMeters': distanceMeters.round(),
    'spotId': spot?.id ?? '',
    'spotName': spot?.name ?? '',
    'spotCategory': spot?.categories.isEmpty == true
        ? ''
        : spot?.categories.first ?? '',
    'read': false,
    'lastNotifiedAtMillis': nowMillis,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> checkFriendLocationNotifications() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  final friendUids = await loadCurrentFriendUids();

  if (friendUids.isEmpty) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .get();

  final friendUidSet = friendUids.toSet();
  final friendLocations = activeLocations.docs
      .map((doc) => LiveLocationData.fromFirestore(doc))
      .where(
        (location) =>
            friendUidSet.contains(location.uid) &&
            location.uid != firebaseUser.uid &&
            !location.isExpired,
      )
      .toList();

  if (friendLocations.isEmpty) {
    return;
  }

  final currentLocation = await loadCurrentLiveLocationForUser(
    firebaseUser.uid,
  );
  final visibleApprovedSpots = approvedPublicSpots();

  for (final friendLocation in friendLocations) {
    if (currentLocation != null) {
      final distanceMeters = distanceBetweenLatLngMeters(
        currentLocation.coordinates,
        friendLocation.coordinates,
      );

      if (distanceMeters <= friendNearbyRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendNearbyNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_nearby',
          distanceMeters: distanceMeters,
        );
      }
    }

    for (final spot in visibleApprovedSpots) {
      if (spot.id.trim().isEmpty) {
        continue;
      }

      final distanceToSpotMeters = distanceBetweenLatLngMeters(
        friendLocation.coordinates,
        spot.coordinates,
      );

      if (distanceToSpotMeters <= friendAtSpotRadiusMeters) {
        await createFriendLocationNotification(
          notificationId: friendSpotNotificationId(
            firebaseUser.uid,
            friendLocation.uid,
            spot.id,
          ),
          userId: firebaseUser.uid,
          friendLocation: friendLocation,
          type: 'friend_at_spot',
          distanceMeters: distanceToSpotMeters,
          spot: spot,
        );
      }
    }
  }
}

bool get currentUserCanUseVerifiedOnlySpots {
  return currentUser.role == UserRole.admin || currentUser.verified;
}

bool currentUserCanManageSpotBusiness(CarSpot spot) {
  return spot.supportsContacts &&
      (currentUser.role == UserRole.admin ||
          (spot.ownerUid.isNotEmpty && spot.ownerUid == currentUser.uid));
}

Future<String> detectCityCountryForCoordinates(LatLng coordinates) async {
  try {
    final placemarks = await placemarkFromCoordinates(
      coordinates.latitude,
      coordinates.longitude,
    );

    if (placemarks.isEmpty) {
      return 'Unknown location';
    }

    final place = placemarks.first;
    final city =
        [place.locality, place.subAdministrativeArea, place.administrativeArea]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Unknown city',
            );
    final country = (place.country ?? '').trim();

    return country.isEmpty ? city : '$city, $country';
  } catch (_) {
    return 'Unknown location';
  }
}

double distanceBetweenLatLngMeters(LatLng first, LatLng second) {
  return const Distance().as(LengthUnit.Meter, first, second);
}

double normalizedHeadingDegrees(double value, {double fallback = 0}) {
  if (!value.isFinite || value < 0) {
    return fallback;
  }

  final normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

double headingRadiansForMap(double headingDegrees, double mapRotationDegrees) {
  return (headingDegrees - mapRotationDegrees) * math.pi / 180;
}

double bearingBetweenLatLngDegrees(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final deltaLng = (to.longitude - from.longitude) * math.pi / 180;

  final y = math.sin(deltaLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
  final bearing = math.atan2(y, x) * 180 / math.pi;

  return normalizedHeadingDegrees(bearing + 360);
}


Future<void> createMeetSpotNotificationsForNearbyUsers(CarSpot spot) async {
  if (spot.id.trim().isEmpty || !spot.categories.contains('Meet')) {
    return;
  }

  final activeLocations = await liveLocationsCollection()
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .get();
  final batch = FirebaseFirestore.instance.batch();
  var writes = 0;

  for (final doc in activeLocations.docs) {
    final liveLocation = LiveLocationData.fromFirestore(doc);

    if (liveLocation.uid == spot.addedByUid || liveLocation.isExpired) {
      continue;
    }

    final distanceMeters = distanceBetweenLatLngMeters(
      spot.coordinates,
      liveLocation.coordinates,
    );

    if (distanceMeters > 50000) {
      continue;
    }

    final notificationId = '${spot.id}_${liveLocation.uid}';
    final notificationRef = meetNotificationsCollection().doc(notificationId);
    batch.set(notificationRef, {
      'userId': liveLocation.uid,
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'lat': spot.coordinates.latitude,
      'lng': spot.coordinates.longitude,
      'coordinates': GeoPoint(
        spot.coordinates.latitude,
        spot.coordinates.longitude,
      ),
      'distanceMeters': distanceMeters.round(),
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    writes++;
  }

  if (writes > 0) {
    await batch.commit();
  }
}

Future<List<String>> adminUserIdsExcept({String? excludedUid}) async {
  final snapshot = await usersCollection()
      .where('role', isEqualTo: 'admin')
      .get();

  return snapshot.docs
      .map((doc) => stringFromFirebase(doc.data()['uid'], doc.id))
      .where((uid) => uid.isNotEmpty && uid != excludedUid)
      .toList();
}

Future<void> createAdminSpotReviewNotification(CarSpot spot) async {
  if (spot.id.trim().isEmpty || spot.status != SpotStatus.pending) {
    return;
  }

  final adminUids = await adminUserIdsExcept(excludedUid: spot.addedByUid);

  if (adminUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();

  for (final adminUid in adminUids) {
    final notificationRef = adminNotificationsCollection().doc(
      '${spot.id}_review_$adminUid',
    );
    batch.set(notificationRef, {
      'userId': adminUid,
      'type': 'spot_pending_review',
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'addedBy': spot.addedBy,
      'addedByUid': spot.addedByUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  await batch.commit();
}

Future<void> createAdminSpotDecisionNotification(
  CarSpot spot,
  SpotStatus status,
) async {
  if (spot.id.trim().isEmpty ||
      (status != SpotStatus.approved && status != SpotStatus.rejected)) {
    return;
  }

  final adminUids = await adminUserIdsExcept(excludedUid: currentUser.uid);

  if (adminUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();
  final statusName = spotStatusName(status);

  for (final adminUid in adminUids) {
    final notificationRef = adminNotificationsCollection().doc(
      '${spot.id}_${statusName}_$adminUid',
    );
    batch.set(notificationRef, {
      'userId': adminUid,
      'type': status == SpotStatus.approved
          ? 'spot_approved_by_admin'
          : 'spot_rejected_by_admin',
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'status': statusName,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  await batch.commit();
}

class PoliceReportData {
  final String id;
  final String uid;
  final String username;
  final LatLng coordinates;
  final int createdAtMillis;
  final int expiresAtMillis;
  final int updatedAtMillis;
  final String status;
  final List<String> stillThereBy;
  final List<String> notThereBy;

  const PoliceReportData({
    required this.id,
    required this.uid,
    required this.username,
    required this.coordinates,
    required this.createdAtMillis,
    required this.expiresAtMillis,
    required this.updatedAtMillis,
    this.status = 'active',
    this.stillThereBy = const [],
    this.notThereBy = const [],
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAtMillis;
  bool get isActive => status != 'removed' && !isExpired;
  int get stillThereCount => stillThereBy.length;
  int get notThereCount => notThereBy.length;

  bool userPressedStillThere(String? uid) {
    return uid != null && stillThereBy.contains(uid);
  }

  bool userPressedNotThere(String? uid) {
    return uid != null && notThereBy.contains(uid);
  }

  factory PoliceReportData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final geoPoint = data['coordinates'];
    final coordinates = geoPoint is GeoPoint
        ? LatLng(geoPoint.latitude, geoPoint.longitude)
        : LatLng(
            doubleFromFirebase(data['lat'], 56.9496),
            doubleFromFirebase(data['lng'], 24.1052),
          );

    return PoliceReportData(
      id: doc.id,
      uid: stringFromFirebase(data['uid'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      coordinates: coordinates,
      createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
      expiresAtMillis: timestampMillisFromFirebase(data['expiresAt']),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      status: stringFromFirebase(data['status'], 'active'),
      stillThereBy: stringListFromFirebase(data['stillThereBy'], const []),
      notThereBy: stringListFromFirebase(data['notThereBy'], const []),
    );
  }
}

Future<void> saveCurrentUserFields(Map<String, Object?> data) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  await usersCollection().doc(firebaseUser.uid).set({
    ...data,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

CollectionReference<Map<String, dynamic>> spotsCollection() {
  return FirebaseFirestore.instance.collection('spots');
}

Future<String> uploadSpotPhoto({
  required String spotId,
  required String localPhotoPath,
  required String userId,
  required int photoIndex,
}) async {
  if (photoIndex < 0 || photoIndex >= maxSpotGalleryPhotos) {
    throw Exception('Spot photo index is outside the allowed gallery range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = photoIndex == 0
      ? 'spots/$spotId/main.jpg'
      : 'spots/$spotId/gallery/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2SpotPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadUserAvatarPhoto({
  required String userId,
  required String localPhotoPath,
}) async {
  final r2Path = 'users/$userId/avatar.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2AvatarPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadGarageCarPhoto({
  required String userId,
  required int carIndex,
  required int photoIndex,
  required String localPhotoPath,
}) async {
  if (photoIndex < 0 || photoIndex >= maxGaragePhotos) {
    throw Exception('Garage photo index is outside the allowed range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = photoIndex == 0
      ? 'garage/$userId/car_${carIndex}_cover.jpg'
      : 'garage/$userId/car_$carIndex/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2GaragePhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Map<String, Object?> spotToFirestoreData(
  CarSpot spot, {
  bool includeCreatedAt = false,
}) {
  final data = <String, Object?>{
    'name': spot.name,
    'cityCountry': spot.cityCountry,
    'lat': spot.coordinates.latitude,
    'lng': spot.coordinates.longitude,
    'coordinates': GeoPoint(
      spot.coordinates.latitude,
      spot.coordinates.longitude,
    ),
    'description': spot.description,
    'categories': spot.categories,
    'rating': spot.rating,
    'photoUrl': spot.photoUrl,
    'photoUrls': spot.photoUrls,
    'reelLink': spot.reelLink,
    'contactPhone': spot.contactPhone,
    'contactInstagram': spot.contactInstagram,
    'contactEmail': spot.contactEmail,
    'openingHours': openingHoursToFirebase(spot.openingHours),
    'ownerUid': spot.ownerUid,
    'ownerUsername': spot.ownerUsername,
    'bestTime': spot.bestTime,
    'parking': spot.parking,
    'roadQuality': spot.roadQuality,
    'lowCarFriendly': spot.lowCarFriendly,
    'policeRisk': spot.policeRisk,
    'traffic': spot.traffic,
    'lighting': spot.lighting,
    'crowd': spot.crowd,
    'addedBy': spot.addedBy,
    'addedByUid': spot.addedByUid,
    'status': spotStatusName(spot.status),
    'verifiedOnly': spot.verifiedOnly,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (spot.isTemporary) {
    data['isTemporary'] = true;
    data['startsAt'] = spot.startsAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    data['expiresAt'] = spot.expiresAtMillis == null
        ? null
        : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
  } else {
    data['isTemporary'] = false;
    data['startsAt'] = null;
    data['expiresAt'] = null;
  }

  if (includeCreatedAt) {
    data['createdAt'] = FieldValue.serverTimestamp();
  }

  return data;
}

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? spotSyncSubscription;

void startFirebaseSpotSync() {
  spotSyncSubscription?.cancel();
  spotSyncSubscription = spotsCollection().snapshots().listen(
    (snapshot) {
      final firebaseSpots = snapshot.docs
          .map((doc) => CarSpot.fromFirestore(doc))
          .toList();

      reviewSpots.value = firebaseSpots;
      submittedSpots.value = firebaseSpots
          .where(
            (spot) => spot.addedByUid == FirebaseAuth.instance.currentUser?.uid,
          )
          .toList();
    },
    onError: (_) {
      // Firestore rules may still be closed while the user is setting up Firebase.
    },
  );
}

Future<void> refreshFirebaseSpotsFromServer() async {
  final snapshot = await spotsCollection().get(
    const GetOptions(source: Source.server),
  );
  final firebaseSpots = snapshot.docs
      .map((doc) => CarSpot.fromFirestore(doc))
      .toList();

  reviewSpots.value = firebaseSpots;
  submittedSpots.value = firebaseSpots
      .where(
        (spot) => spot.addedByUid == FirebaseAuth.instance.currentUser?.uid,
      )
      .toList();
}

class SpotReviewData {
  final String id;
  final String spotId;
  final String userId;
  final String username;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const SpotReviewData({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.username,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory SpotReviewData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final timestamp = data['createdAt'];

    return SpotReviewData(
      id: doc.id,
      spotId: stringFromFirebase(data['spotId'], ''),
      userId: stringFromFirebase(data['userId'], ''),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      rating: doubleFromFirebase(data['rating'], 5).round().clamp(1, 5).toInt(),
      comment: stringFromFirebase(data['comment'], ''),
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

CollectionReference<Map<String, dynamic>> spotReviewsCollection() {
  return FirebaseFirestore.instance.collection('spot_reviews');
}

CollectionReference<Map<String, dynamic>> spotLikesCollection() {
  return FirebaseFirestore.instance.collection('spot_likes');
}

const int maxCommentsPerUserPerSpot = 50;

String spotReviewKey(CarSpot spot) {
  if (spot.id.trim().isNotEmpty) {
    return spot.id.trim();
  }

  final safeName = spot.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  return safeName.isEmpty ? 'demo_spot' : 'demo_$safeName';
}

Stream<List<SpotReviewData>> watchSpotReviews(CarSpot spot) {
  return spotReviewsCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .snapshots()
      .map((snapshot) {
        final reviews = snapshot.docs
            .map((doc) => SpotReviewData.fromFirestore(doc))
            .where((review) => review.comment.isNotEmpty)
            .toList();

        reviews.sort(
          (first, second) => second.createdAt.compareTo(first.createdAt),
        );
        return reviews;
      });
}

Stream<int> watchSpotCommentCount(CarSpot spot) {
  return watchSpotReviews(spot).map((reviews) => reviews.length);
}

Stream<int> watchSpotLikeCount(CarSpot spot) {
  return spotLikesCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}

Stream<bool> watchCurrentUserLikedSpot(CarSpot spot) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  return spotLikesCollection()
      .doc('${spotReviewKey(spot)}_${firebaseUser.uid}')
      .snapshots()
      .map((snapshot) => snapshot.exists);
}

Future<void> toggleSpotLike(
  BuildContext context,
  CarSpot spot,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Log in before liking spots.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final likeRef = spotLikesCollection().doc(
    '${spotReviewKey(spot)}_${firebaseUser.uid}',
  );

  if (currentlyLiked) {
    await likeRef.delete();
  } else {
    await likeRef.set({
      'spotId': spotReviewKey(spot),
      'spotName': spot.name,
      'userId': firebaseUser.uid,
      'username': currentUser.username,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

String commentLikeDocumentId(SpotReviewData review, String userId) {
  return 'comment_${review.id}_$userId';
}

Stream<int> watchCommentLikeCount(SpotReviewData review) {
  return spotLikesCollection()
      .where('commentId', isEqualTo: review.id)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}

Stream<bool> watchCurrentUserLikedComment(SpotReviewData review) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(false);
  }

  return spotLikesCollection()
      .doc(commentLikeDocumentId(review, firebaseUser.uid))
      .snapshots()
      .map((snapshot) => snapshot.exists);
}

Future<void> toggleCommentLike(
  BuildContext context,
  SpotReviewData review,
  bool currentlyLiked,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Log in before liking comments.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final likeRef = spotLikesCollection().doc(
    commentLikeDocumentId(review, firebaseUser.uid),
  );

  if (currentlyLiked) {
    await likeRef.delete();
  } else {
    await likeRef.set({
      'targetType': 'comment',
      'commentId': review.id,
      'commentSpotId': review.spotId,
      'userId': firebaseUser.uid,
      'username': currentUser.username,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

Future<void> saveSpotReview({
  required CarSpot spot,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before leaving a review.',
    );
  }

  final spotId = spotReviewKey(spot);
  final cleanComment = comment.trim();

  final existingReviews = await spotReviewsCollection()
      .where('spotId', isEqualTo: spotId)
      .get();

  final userCommentCount = existingReviews.docs.where((doc) {
    final data = doc.data();
    return stringFromFirebase(data['userId'], '') == firebaseUser.uid &&
        stringFromFirebase(data['comment'], '').trim().isNotEmpty;
  }).length;

  if (userCommentCount >= maxCommentsPerUserPerSpot) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'comment-limit-reached',
      message: 'You reached the 50 comment limit for this spot.',
    );
  }

  await spotReviewsCollection().add({
    'spotId': spotId,
    'spotName': spot.name,
    'type': 'comment',
    'userId': firebaseUser.uid,
    'username': currentUser.username,
    'comment': cleanComment,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> editSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
  required String comment,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before editing a review.',
    );
  }

  if (firebaseUser.uid != review.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can edit only your own comments.',
    );
  }

  final cleanComment = comment.trim();
  if (cleanComment.isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'empty-comment',
      message: 'Comment cannot be empty.',
    );
  }

  await spotReviewsCollection().doc(review.id).update({
    'comment': cleanComment,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> deleteSpotReview({
  required CarSpot spot,
  required SpotReviewData review,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before deleting a review.',
    );
  }

  if (firebaseUser.uid != review.userId) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can delete only your own comments.',
    );
  }

  await spotReviewsCollection().doc(review.id).delete();
}

String spotRatingDocumentId(CarSpot spot, String userId) {
  return '${spotReviewKey(spot)}_${userId}_rating';
}

Stream<int> watchCurrentUserSpotRating(CarSpot spot) {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(0);
  }

  return spotReviewsCollection()
      .doc(spotRatingDocumentId(spot, firebaseUser.uid))
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();

        if (!snapshot.exists || data == null) {
          return 0;
        }

        return doubleFromFirebase(
          data['rating'],
          0,
        ).round().clamp(0, 5).toInt();
      });
}

Future<double?> saveSpotRating({
  required CarSpot spot,
  required int rating,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before rating a spot.',
    );
  }

  final safeRating = rating.clamp(1, 5);
  final ratingRef = spotReviewsCollection().doc(
    spotRatingDocumentId(spot, firebaseUser.uid),
  );
  final ratingSnapshot = await ratingRef.get();

  final data = <String, Object?>{
    'spotId': spotReviewKey(spot),
    'spotName': spot.name,
    'type': 'rating',
    'userId': firebaseUser.uid,
    'username': currentUser.username,
    'rating': safeRating,
    'comment': '',
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (!ratingSnapshot.exists) {
    data['createdAt'] = FieldValue.serverTimestamp();
  }

  await ratingRef.set(data, SetOptions(merge: true));

  return updateSpotRatingFromReviews(spot);
}

Future<double?> updateSpotRatingFromReviews(CarSpot spot) async {
  if (spot.id.trim().isEmpty) {
    return null;
  }

  final snapshot = await spotReviewsCollection()
      .where('spotId', isEqualTo: spotReviewKey(spot))
      .get();

  final ratings = snapshot.docs
      .map((doc) => doc.data())
      .where((data) => stringFromFirebase(data['type'], '') == 'rating')
      .map((data) => doubleFromFirebase(data['rating'], 0))
      .where((rating) => rating >= 1 && rating <= 5)
      .toList();

  if (ratings.isEmpty) {
    return null;
  }

  final averageRating =
      ratings.fold<double>(0, (total, rating) => total + rating) /
      ratings.length;
  final roundedRating = double.parse(averageRating.toStringAsFixed(1));

  await spotsCollection().doc(spot.id).update({
    'rating': roundedRating,
    'ratingCount': ratings.length,
    'reviewUpdatedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  final updatedSpot = spot.copyWith(rating: roundedRating);

  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();

  return roundedRating;
}

const demoSpots = [
  CarSpot(
    name: 'Andrejsala Harbor',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9612, 24.0944),
    description:
        'Industrial harbor mood, wide roads, dark water reflections, and a strong night shoot atmosphere.',
    categories: ['Photo', 'Reels', 'Meet'],
    rating: 4.8,
    photoUrl:
        'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-andrejsala',
    bestTime: 'Night',
    parking: 'Easy',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Medium',
    traffic: 'Low',
    lighting: 'Street lights',
    crowd: 'Medium',
    addedBy: 'riga_driver',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Spikeri Brick Yard',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9427, 24.1168),
    description:
        'Brick walls, city texture, and clean angles for rollers, portraits, and parked car shots.',
    categories: ['Photo', 'Reels'],
    rating: 4.6,
    photoUrl:
        'https://images.unsplash.com/photo-1542362567-b07e54358753?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://tiktok.com/@ccs/video/demo-spikeri',
    bestTime: 'Golden hour',
    parking: 'Street',
    roadQuality: 'Mixed',
    lowCarFriendly: false,
    policeRisk: 'Low',
    traffic: 'Medium',
    lighting: 'Warm city lights',
    crowd: 'Low',
    addedBy: 'stance_lv',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Bikernieki Forest Road',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9662, 24.2294),
    description:
        'Forest road energy near the track area. Best for clean rolling content and small meets.',
    categories: ['Drive', 'Meet', 'Reels'],
    rating: 4.7,
    photoUrl:
        'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-bikernieki',
    bestTime: 'Evening',
    parking: 'Good',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'Low',
    traffic: 'Low',
    lighting: 'Natural',
    crowd: 'Low',
    addedBy: 'jdm_riga',
    status: SpotStatus.approved,
  ),
  CarSpot(
    name: 'Riga Rooftop Parking',
    cityCountry: 'Riga, Latvia',
    coordinates: LatLng(56.9497, 24.1052),
    description:
        'Skyline view and clean concrete lines. This spot is waiting for moderator approval.',
    categories: ['Photo', 'Low car'],
    rating: 4.4,
    photoUrl:
        'https://images.unsplash.com/photo-1511919884226-fd3cad34687c?q=80&w=1200&auto=format&fit=crop',
    reelLink: 'https://instagram.com/reel/demo-pending',
    bestTime: 'Sunset',
    parking: 'Private',
    roadQuality: 'Good',
    lowCarFriendly: true,
    policeRisk: 'High',
    traffic: 'Medium',
    lighting: 'Rooftop lights',
    crowd: 'Unknown',
    addedBy: 'new_spotter',
    status: SpotStatus.pending,
  ),
];

List<CarSpot> approvedPublicSpots() {
  // Public Explore/Map must show only real Firebase spots.
  // Demo spots stay in code as backup data, but they should not reappear
  // after an admin deletes an approved Firebase spot.
  return reviewSpots.value
      .where(
        (spot) =>
            spot.status == SpotStatus.approved &&
            spot.isVisibleNow &&
            (!spot.verifiedOnly || currentUserCanUseVerifiedOnlySpots),
      )
      .toList();
}

List<CarSpot> pendingReviewSpots() {
  return reviewSpots.value
      .where((spot) => spot.status == SpotStatus.pending)
      .toList();
}

bool isSameSpot(CarSpot first, CarSpot second) {
  if (first.id.isNotEmpty && second.id.isNotEmpty) {
    return first.id == second.id;
  }

  return first.name == second.name && first.addedBy == second.addedBy;
}

Future<void> updateSpotStatus(CarSpot spot, SpotStatus status) async {
  final statusChanged = spot.status != status;
  final shouldNotifyNearbyMeetUsers =
      status == SpotStatus.approved &&
      spot.status != SpotStatus.approved &&
      spot.categories.contains('Meet');
  final shouldNotifyOtherAdmins =
      statusChanged &&
      (status == SpotStatus.approved || status == SpotStatus.rejected);

  final updatedSpot = spot.copyWith(
    status: status,
    rating: status == SpotStatus.approved && spot.rating == 0
        ? 4.5
        : spot.rating,
  );

  if (spot.id.isNotEmpty) {
    await spotsCollection().doc(spot.id).update({
      'status': spotStatusName(status),
      'rating': updatedSpot.rating,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Keep the local UI responsive while Firestore sends the fresh snapshot.
  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();

  if (shouldNotifyNearbyMeetUsers) {
    await createMeetSpotNotificationsForNearbyUsers(updatedSpot);
  }

  if (shouldNotifyOtherAdmins) {
    await createAdminSpotDecisionNotification(updatedSpot, status);
  }
}

Future<void> deleteSpotFromFirebase(CarSpot spot) async {
  if (spot.id.isNotEmpty) {
    await spotsCollection().doc(spot.id).delete();
  }

  reviewSpots.value = reviewSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  submittedSpots.value = submittedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  savedSpots.value = savedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'CCS',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: blue,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'COMMUNITY CAR SPOTS',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 3,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'FIND - DRIVE - SHOOT',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 4,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 80),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 42,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'ENTER CCS',
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 2,
                    color: Colors.white,
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isSigningIn = false;
  bool rememberMe = rememberMeEnabled;

  Widget loginButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Future<void> loginWithGoogle() async {
    setState(() => isSigningIn = true);

    try {
      await signInWithGoogleAndSaveUser();
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Google login failed. Check Firebase Google sign-in setup. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  Future<void> loginWithTelegram() async {
    setState(() => isSigningIn = true);

    try {
      await signInWithTelegramAndSaveUser();
      await saveRememberMePreference(rememberMe);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Telegram login failed. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.68)),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'CCS',
                  style: TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: blue,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'COMMUNITY CAR SPOTS',
                  style: TextStyle(letterSpacing: 3, color: Colors.white70),
                ),
                const SizedBox(height: 60),
                loginButton(
                  isSigningIn ? 'Signing in...' : 'Continue with Google',
                  Icons.g_mobiledata,
                  Colors.red,
                  isSigningIn ? null : loginWithGoogle,
                ),
                loginButton(
                  'Continue with Telegram',
                  Icons.send,
                  blue,
                  isSigningIn ? null : loginWithTelegram,
                ),
                const SizedBox(height: 4),
                _RememberMeRow(
                  value: rememberMe,
                  enabled: !isSigningIn,
                  onChanged: (value) => setState(() => rememberMe = value),
                ),
                const SizedBox(height: 28),
                const Text(
                  'By continuing, you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RememberMeRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _RememberMeRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: enabled
                  ? (checked) => onChanged(checked ?? false)
                  : null,
              activeColor: blue,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            const SizedBox(width: 4),
            const Text(
              'Remember me',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  meetNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  adminNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  friendLocationNotificationSubscription;
  Timer? friendLocationCheckTimer;
  bool isCheckingFriendLocationNotifications = false;

  final screens = const [
    ExploreScreen(),
    MapScreen(),
    AddSpotScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    startMeetNotificationListener();
    startAdminNotificationListener();
    startFriendLocationNotificationListener();
    startFriendLocationNotificationChecks();
  }

  void startMeetNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    meetNotificationSubscription = meetNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final spotName = stringFromFirebase(
              data['spotName'],
              'New meet spot',
            );
            final distanceMeters = doubleFromFirebase(
              data['distanceMeters'],
              0,
            );
            final distanceKm = distanceMeters <= 0
                ? ''
                : ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away';

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: blue,
                  content: Text(
                    'New meet nearby: $spotName$distanceKm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.set({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startAdminNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null || currentUser.role != UserRole.admin) {
      return;
    }

    adminNotificationSubscription = adminNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final type = stringFromFirebase(data['type'], '');
            final spotName = stringFromFirebase(data['spotName'], 'New spot');
            final addedBy = stringFromFirebase(data['addedBy'], 'user');
            final reviewedBy = stringFromFirebase(data['reviewedBy'], 'admin');

            final message = switch (type) {
              'spot_pending_review' =>
                'New spot waiting for review: $spotName by $addedBy',
              'spot_approved_by_admin' =>
                '$reviewedBy approved spot: $spotName',
              'spot_rejected_by_admin' =>
                '$reviewedBy rejected spot: $spotName',
              _ => 'Admin update: $spotName',
            };

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: panel,
                  content: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.set({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startFriendLocationNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    friendLocationNotificationSubscription =
        friendLocationNotificationsCollection()
            .where('userId', isEqualTo: firebaseUser.uid)
            .snapshots()
            .listen((snapshot) async {
              for (final change in snapshot.docChanges) {
                if (change.type != DocumentChangeType.added &&
                    change.type != DocumentChangeType.modified) {
                  continue;
                }

                final data = change.doc.data() ?? {};

                if (data['read'] == true) {
                  continue;
                }

                final type = stringFromFirebase(data['type'], 'friend_nearby');
                final friendUsername = stringFromFirebase(
                  data['friendUsername'],
                  'friend',
                );
                final spotName = stringFromFirebase(data['spotName'], 'a spot');
                final distanceMeters = doubleFromFirebase(
                  data['distanceMeters'],
                  0,
                );
                final distanceLabel = distanceMeters <= 0
                    ? ''
                    : distanceMeters >= 1000
                    ? ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away'
                    : ' • ${distanceMeters.round()} m away';

                final message = type == 'friend_at_spot'
                    ? '@$friendUsername is at $spotName$distanceLabel'
                    : '@$friendUsername is nearby$distanceLabel';

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.greenAccent.shade700,
                      content: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                await change.doc.reference.set({
                  'read': true,
                  'readAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              }
            });
  }

  void startFriendLocationNotificationChecks() {
    runFriendLocationNotificationCheck();
    friendLocationCheckTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => runFriendLocationNotificationCheck(),
    );
  }

  Future<void> runFriendLocationNotificationCheck() async {
    if (isCheckingFriendLocationNotifications) {
      return;
    }

    isCheckingFriendLocationNotifications = true;

    try {
      await checkFriendLocationNotifications();
    } catch (_) {
      // Friend location notifications are best-effort in-app alerts.
    } finally {
      isCheckingFriendLocationNotifications = false;
    }
  }

  @override
  void dispose() {
    meetNotificationSubscription?.cancel();
    adminNotificationSubscription?.cancel();
    friendLocationNotificationSubscription?.cancel();
    friendLocationCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (value) => setState(() => index = value),
        selectedItemColor: blue,
        unselectedItemColor: Colors.white54,
        backgroundColor: panel,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Spots',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Add Spot',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

enum ExploreSortMode { trending, old, newest, popular, meet }

String exploreSortLabel(ExploreSortMode mode) {
  switch (mode) {
    case ExploreSortMode.trending:
      return 'Trending';
    case ExploreSortMode.old:
      return 'Old';
    case ExploreSortMode.newest:
      return 'New';
    case ExploreSortMode.popular:
      return 'Popular';
    case ExploreSortMode.meet:
      return 'Meet';
  }
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  ExploreSortMode selectedMode = ExploreSortMode.trending;
  final Set<String> enabledCategoryFilters = {...spotCategoryOptions};
  bool showSavedOnly = false;

  @override
  void initState() {
    super.initState();
    savedSpots.addListener(refreshSavedFilter);
  }

  @override
  void dispose() {
    savedSpots.removeListener(refreshSavedFilter);
    super.dispose();
  }

  void refreshSavedFilter() {
    if (mounted && showSavedOnly) {
      setState(() {});
    }
  }

  List<CarSpot> sortedSpots(List<CarSpot> spots) {
    final list = [...spots];

    if (selectedMode == ExploreSortMode.meet) {
      list.removeWhere((spot) => !spot.categories.contains('Meet'));
    }

    switch (selectedMode) {
      case ExploreSortMode.trending:
        list.sort((a, b) {
          final ratingCompare = b.rating.compareTo(a.rating);
          if (ratingCompare != 0) {
            return ratingCompare;
          }
          return b.createdAtMillis.compareTo(a.createdAtMillis);
        });
        break;
      case ExploreSortMode.old:
        list.sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));
        break;
      case ExploreSortMode.newest:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
      case ExploreSortMode.popular:
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case ExploreSortMode.meet:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
    }

    return list;
  }

  List<CarSpot> filteredSpots() {
    if (enabledCategoryFilters.isEmpty) {
      return const [];
    }

    return approvedPublicSpots().where((spot) {
      if (!spot.categories.any(enabledCategoryFilters.contains)) {
        return false;
      }

      if (!showSavedOnly) {
        return true;
      }

      return savedSpots.value.any((saved) => isSameSpot(saved, spot));
    }).toList();
  }

  Map<String, List<CarSpot>> groupedSpotsByCategory(List<CarSpot> spots) {
    final grouped = <String, List<CarSpot>>{};

    for (final category in spotCategoryOptions) {
      final categorySpots = spots
          .where((spot) => primarySpotCategory(spot) == category)
          .toList();
      final sortedCategorySpots = sortedSpots(categorySpots);

      if (sortedCategorySpots.isNotEmpty) {
        grouped[category] = sortedCategorySpots;
      }
    }

    return grouped;
  }

  Future<void> showExploreCategoryFilterSheet() async {
    final nextEnabledCategories = Set<String>.from(enabledCategoryFilters);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;

            void selectAll() {
              setSheetState(() {
                nextEnabledCategories
                  ..clear()
                  ..addAll(spotCategoryOptions);
              });
            }

            void clearAll() {
              setSheetState(nextEnabledCategories.clear);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Explore filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'All categories enabled'
                          : '$selectedCount of ${spotCategoryOptions.length} categories enabled',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: selectAll,
                          icon: const Icon(Icons.done_all),
                          label: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: clearAll,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final category in spotCategoryOptions)
                              CheckboxListTile(
                                value: nextEnabledCategories.contains(category),
                                onChanged: (enabled) {
                                  setSheetState(() {
                                    if (enabled == true) {
                                      nextEnabledCategories.add(category);
                                    } else {
                                      nextEnabledCategories.remove(category);
                                    }
                                  });
                                },
                                dense: true,
                                activeColor: spotColorForCategory(category),
                                checkColor: Colors.black,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: spotColorForCategory(category),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            enabledCategoryFilters
                              ..clear()
                              ..addAll(nextEnabledCategories);
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget sortChip(ExploreSortMode mode) {
    final selected = selectedMode == mode;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(exploreSortLabel(mode)),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => selectedMode = mode),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget savedFilterChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: const Text('Saved'),
        avatar: Icon(
          showSavedOnly ? Icons.bookmark : Icons.bookmark_border,
          color: showSavedOnly ? Colors.white : Colors.white70,
          size: 18,
        ),
        selected: showSavedOnly,
        showCheckmark: false,
        onSelected: (value) => setState(() => showSavedOnly = value),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: showSavedOnly ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: showSavedOnly ? Colors.white : Colors.white70,
          fontWeight: showSavedOnly ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: reviewSpots,
      builder: (context, _, _) {
        final approvedSpots = filteredSpots();
        final groupedSpots = groupedSpotsByCategory(approvedSpots);
        final selectedCount = enabledCategoryFilters.length;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('CCS'),
            backgroundColor: Colors.black,
            foregroundColor: blue,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      tooltip: 'Filters',
                      onPressed: showExploreCategoryFilterSheet,
                      icon: const Icon(Icons.tune),
                    ),
                    if (selectedCount != spotCategoryOptions.length)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spots',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Approved car spots',
                          style: TextStyle(color: Colors.white54, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: showExploreCategoryFilterSheet,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'Filters'
                          : '$selectedCount/${spotCategoryOptions.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    sortChip(ExploreSortMode.trending),
                    sortChip(ExploreSortMode.old),
                    sortChip(ExploreSortMode.newest),
                    sortChip(ExploreSortMode.popular),
                    sortChip(ExploreSortMode.meet),
                    savedFilterChip(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (groupedSpots.isEmpty)
                EmptyStateCard(
                  icon: Icons.explore,
                  title: showSavedOnly
                      ? 'No saved spots yet'
                      : approvedPublicSpots().isEmpty
                      ? 'No spots here yet'
                      : 'No spots match your filters',
                  text: showSavedOnly
                      ? 'Tap the bookmark on a spot to keep it here.'
                      : approvedPublicSpots().isEmpty
                      ? 'Approved spots will appear here after moderation.'
                      : 'Open filters and enable more categories to see more spots.',
                )
              else
                for (final entry in groupedSpots.entries) ...[
                  ExploreCategoryHeader(
                    category: entry.key,
                    count: entry.value.length,
                  ),
                  const SizedBox(height: 10),
                  for (final spot in entry.value) ...[
                    ExploreSpotCard(spot: spot),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 6),
                ],
            ],
          ),
        );
      },
    );
  }
}

class ExploreCategoryHeader extends StatelessWidget {
  final String category;
  final int count;

  const ExploreCategoryHeader({
    super.key,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final color = spotColorForCategory(category);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class ExploreSpotCard extends StatelessWidget {
  final CarSpot spot;

  const ExploreSpotCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final visibleCategories = <String>{
      for (final category in spot.categories)
        if (category.trim().isNotEmpty) category.trim(),
    }.take(3).toList();

    final tagWidgets = <Widget>[
      if (spot.isTemporary)
        _SmallTag(label: spot.temporaryTimeLabel, icon: Icons.event),
      for (final category in visibleCategories)
        _SmallTag(label: category, icon: Icons.local_offer),
    ];
    final addedDateText = spot.createdAtMillis > 0
        ? 'Added ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis))}'
        : 'Added date unknown';
    final categoryColor = spotColorForSpot(spot);
    final addedByText = spot.addedBy.trim().isEmpty
        ? 'Added by: unknown'
        : 'Added by: ${spot.addedBy}';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: categoryColor.withValues(alpha: 0.85),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: categoryColor.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 136,
              child: Column(
                children: [
                  Stack(
                    children: [
                      SpotPhoto(
                        spot: spot,
                        width: 136,
                        height: 106,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Transform.scale(
                          scale: 0.72,
                          alignment: Alignment.topRight,
                          child: SaveSpotButton(spot: spot, compact: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExploreSpotStatsRow(spot: spot),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Icon(Icons.star, color: blue, size: 15),
                      const SizedBox(width: 3),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: Colors.white38,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          addedDateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: Colors.white38,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: spot.addedByUid.trim().isEmpty
                            ? Text(
                                addedByText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : InkWell(
                                onTap: () => openUserProfile(
                                  context,
                                  uid: spot.addedByUid,
                                  fallbackUsername: spot.addedBy,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                child: Text(
                                  'Added by @${spot.addedBy.replaceAll('@', '')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: blue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spot.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tagWidgets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) => tagWidgets[index],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExploreSpotStatsRow extends StatelessWidget {
  final CarSpot spot;
  final bool overlay;

  const ExploreSpotStatsRow({
    super.key,
    required this.spot,
    this.overlay = false,
  });

  Widget simpleStat({
    required IconData icon,
    required int count,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: overlay ? 16 : 18),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: overlay ? 12 : 13,
            fontWeight: FontWeight.w900,
            shadows: overlay
                ? const [Shadow(color: Colors.black, blurRadius: 5)]
                : null,
          ),
        ),
      ],
    );

    if (overlay) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: content,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.42)),
        ),
        child: content,
      ),
    );
  }

  Widget statsDivider() {
    if (overlay) {
      return const SizedBox(width: 5);
    }

    return const SizedBox(width: 7);
  }

  Stream<bool> currentUserCommentedStream() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return Stream.value(false);
    }

    return watchSpotReviews(spot).map(
      (reviews) => reviews.any(
        (review) =>
            review.userId == firebaseUser.uid && review.comment.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inactiveColor = overlay
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.white70;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<bool>(
          stream: watchCurrentUserLikedSpot(spot),
          builder: (context, likedSnapshot) {
            final liked = likedSnapshot.data ?? false;

            return StreamBuilder<int>(
              stream: watchSpotLikeCount(spot),
              builder: (context, countSnapshot) {
                final likeCount = countSnapshot.data ?? 0;

                return simpleStat(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  count: likeCount,
                  color: liked ? Colors.redAccent : inactiveColor,
                  onTap: () => toggleSpotLike(context, spot, liked),
                );
              },
            );
          },
        ),
        statsDivider(),
        StreamBuilder<bool>(
          stream: currentUserCommentedStream(),
          builder: (context, commentedSnapshot) {
            final commented = commentedSnapshot.data ?? false;

            return StreamBuilder<int>(
              stream: watchSpotCommentCount(spot),
              builder: (context, countSnapshot) {
                final commentCount = countSnapshot.data ?? 0;

                return simpleStat(
                  icon: commented
                      ? Icons.chat_bubble
                      : Icons.chat_bubble_outline,
                  count: commentCount,
                  color: commented ? blue : inactiveColor,
                  onTap: () => showSpotCommentComposer(context, spot),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

Future<void> showSpotCommentComposer(
  BuildContext context,
  CarSpot spot,
) async {
  final controller = TextEditingController();
  var isSaving = false;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> submitComment() async {
            final comment = controller.text.trim();

            if (comment.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Colors.redAccent,
                  content: Text(
                    'Write a comment first.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
              return;
            }

            setSheetState(() => isSaving = true);

            try {
              await saveSpotReview(spot: spot, comment: comment);

              if (!modalContext.mounted) {
                return;
              }

              Navigator.pop(modalContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: blue,
                  content: Text(
                    'Comment posted.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            } catch (error) {
              if (!modalContext.mounted) {
                return;
              }

              final code = error is FirebaseException
                  ? error.code
                  : error.toString();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.redAccent,
                  content: Text(
                    'Could not save comment: $code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            } finally {
              if (modalContext.mounted) {
                setSheetState(() => isSaving = false);
              }
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                18 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Comment ${spot.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(modalContext),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Write a comment',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : submitComment,
                      icon: Icon(isSaving ? Icons.hourglass_top : Icons.send),
                      label: Text(isSaving ? 'Posting...' : 'Post Comment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  controller.dispose();
}

class CurrentUserTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final triangle = ui.Path()
      ..moveTo(centerX, size.height * 0.10)
      ..lineTo(size.width * 0.22, size.height * 0.86)
      ..quadraticBezierTo(
        centerX,
        size.height * 0.72,
        size.width * 0.78,
        size.height * 0.86,
      )
      ..close();

    final shadowPaint = Paint()
      ..color = const Color(0xFF4DDCFF).withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(triangle.shift(const Offset(0, 2)), shadowPaint);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9BEFFF), Color(0xFF1AAFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(triangle, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(triangle, borderPaint);

    final centerPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(centerX, size.height * 0.51), 3.6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Default map view: open Riga area first, do not auto-jump to the user.
  static const rigaCenter = LatLng(56.9496, 24.1052);
  static const rigaZoom = 11.25;
  static const fullSpotIconMinZoom = 10;
  static const navigationZoom = 16.35;

  final mapController = MapController();
  Timer? temporarySpotRefreshTimer;
  Timer? liveLocationUploadTimer;
  Timer? liveLocationPromptTimer;
  Timer? liveLocationAutoStopTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  liveLocationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  policeReportSubscription;
  final Set<String> enabledCategoryFilters = {...spotCategoryOptions};
  CarSpot? selectedSpot;
  PoliceReportData? selectedPoliceReport;
  LatLng? currentUserLocation;
  bool isLocatingUser = false;
  bool isAddingPoliceReport = false;
  bool isVotingPoliceReport = false;
  bool isSharingLiveLocation = false;
  static const double policeReportVoteRadiusMeters = 300;
  static const Duration policeReportCreatorVoteCooldown = Duration(minutes: 15);
  bool isTogglingLiveLocation = false;
  bool liveLocationPromptOpen = false;
  DateTime? liveLocationPromptAt;
  DateTime? liveLocationExpiresAt;
  List<LiveLocationData> liveLocations = [];
  Set<String> friendLiveLocationUids = {};
  List<PoliceReportData> policeReports = [];
  double currentMapZoom = rigaZoom;
  double currentMapRotationDegrees = 0;
  double currentUserHeadingDegrees = 0;
  LatLng? previousUserLocationForHeading;
  bool mapCenteredOnCurrentUser = false;

  @override
  void initState() {
    super.initState();
    reviewSpots.addListener(refreshMap);

    // Temporary spots can become visible or expire just because time passes.
    // Firestore will not send a new snapshot at the start/end time, so the map
    // needs a small live refresh while this screen is open.
    temporarySpotRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refreshMap(),
    );
    startLiveLocationSync();
    loadFriendLiveLocationUids();
    startPoliceReportSync();
  }

  void refreshMap() {
    if (!mounted) {
      return;
    }

    setState(() {
      final spot = selectedSpot;
      final policeReport = selectedPoliceReport;

      if (spot != null && !spot.isVisibleNow) {
        selectedSpot = null;
      }

      if (policeReport != null && !policeReport.isActive) {
        selectedPoliceReport = null;
      }
    });
  }

  List<CarSpot> get visibleSpots {
    return approvedPublicSpots().where((spot) {
      if (spot.status != SpotStatus.approved) {
        return false;
      }

      if (enabledCategoryFilters.isEmpty) {
        return false;
      }

      return spot.categories.any(enabledCategoryFilters.contains);
    }).toList();
  }

  Future<void> showMapCategoryFilterSheet() async {
    final nextEnabledCategories = Set<String>.from(enabledCategoryFilters);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;

            void selectAll() {
              setSheetState(() {
                nextEnabledCategories
                  ..clear()
                  ..addAll(spotCategoryOptions);
              });
            }

            void clearAll() {
              setSheetState(nextEnabledCategories.clear);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Map filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedCount == spotCategoryOptions.length
                          ? 'All categories enabled'
                          : '$selectedCount of ${spotCategoryOptions.length} categories enabled',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: selectAll,
                          icon: const Icon(Icons.done_all),
                          label: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: clearAll,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final category in spotCategoryOptions)
                              CheckboxListTile(
                                value: nextEnabledCategories.contains(category),
                                onChanged: (enabled) {
                                  setSheetState(() {
                                    if (enabled == true) {
                                      nextEnabledCategories.add(category);
                                    } else {
                                      nextEnabledCategories.remove(category);
                                    }
                                  });
                                },
                                dense: true,
                                activeColor: spotColorForCategory(category),
                                checkColor: Colors.black,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: spotColorForCategory(category),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            enabledCategoryFilters
                              ..clear()
                              ..addAll(nextEnabledCategories);
                            selectedSpot = null;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Marker> get markers {
    final showFullIcons = currentMapZoom >= fullSpotIconMinZoom;

    return visibleSpots.map((spot) {
      final closedNow = spotIsClosedNow(spot);
      final markerColor = closedNow ? Colors.grey.shade500 : spotColorForSpot(spot);
      final markerSize = showFullIcons ? 70.0 : 26.0;
      final markerWidth = showFullIcons ? 122.0 : markerSize;
      final markerHeight = showFullIcons ? 112.0 : markerSize;

      return Marker(
        point: spot.coordinates,
        width: markerWidth,
        height: markerHeight,
        child: GestureDetector(
          onTap: () {
            setState(() => selectedSpot = spot);
          },
          child: showFullIcons
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      left: 2,
                      right: 2,
                      child: IgnorePointer(
                        child: Text(
                          spot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: closedNow
                                ? Colors.white.withValues(alpha: 0.46)
                                : Colors.white.withValues(alpha: 0.74),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: markerSize,
                      height: markerSize,
                      child: closedNow
                          ? ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                markerColor,
                                BlendMode.srcATop,
                              ),
                              child: Opacity(
                                opacity: 0.58,
                                child: Image.asset(
                                  spotIconAssetPathForSpot(spot),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return CompactSpotMapPoint(
                                      color: markerColor,
                                    );
                                  },
                                ),
                              ),
                            )
                          : Image.asset(
                              spotIconAssetPathForSpot(spot),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return CompactSpotMapPoint(color: markerColor);
                              },
                            ),
                    ),
                  ],
                )
              : CompactSpotMapPoint(color: markerColor),
        ),
      );
    }).toList();
  }

  List<Marker> get allMapMarkers {
    final allMarkers = [
      ...markers,
      ...policeReportMarkers,
      ...liveLocationMarkers,
    ];
    final userMarker = currentUserMarker;

    if (userMarker != null) {
      allMarkers.add(userMarker);
    }

    return allMarkers;
  }

  List<PoliceReportData> get visiblePoliceReports {
    return policeReports.where((report) => report.isActive).toList();
  }

  List<Marker> get policeReportMarkers {
    return visiblePoliceReports.map((report) {
      return Marker(
        point: report.coordinates,
        width: 62,
        height: 62,
        child: GestureDetector(
          onTap: () {
            setState(() {
              selectedPoliceReport = report;
              selectedSpot = null;
            });
          },
          child: Tooltip(
            message: 'Police marked by @${report.username}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.62),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.32),
                    blurRadius: 18,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent, width: 2),
                  ),
                  child: const Icon(
                    Icons.local_police,
                    color: Colors.redAccent,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> loadFriendLiveLocationUids() async {
    try {
      final friendUids = await loadCurrentFriendUids();

      if (!mounted) {
        return;
      }

      setState(() => friendLiveLocationUids = friendUids.toSet());
    } catch (_) {
      // Friend icon highlighting is best-effort.
    }
  }

  bool liveLocationIsFriend(LiveLocationData location) {
    return friendLiveLocationUids.contains(location.uid);
  }

  String liveLocationCarIconAsset(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return friendUserCarIconAsset;
    }

    if (location.verified) {
      return verifiedUserCarIconAsset;
    }

    return regularUserCarIconAsset;
  }

  String liveLocationTooltipMessage(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return '@${location.username} is your friend and is sharing live location';
    }

    if (location.verified) {
      return '@${location.username} is verified and is sharing live location';
    }

    return '@${location.username} is sharing live location';
  }

  List<Marker> get liveLocationMarkers {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return liveLocations
        .where((location) => !location.isExpired)
        .where((location) => location.uid != firebaseUser?.uid)
        .map((location) {
          final iconAsset = liveLocationCarIconAsset(location);
          final fallbackColor = liveLocationIsFriend(location)
              ? Colors.purpleAccent
              : location.verified
              ? Colors.greenAccent
              : blue;

          return Marker(
            point: location.coordinates,
            width: 38,
            height: 38,
            rotate: true,
            child: Tooltip(
              message: liveLocationTooltipMessage(location),
              child: Transform.rotate(
                angle: headingRadiansForMap(
                  location.headingDegrees,
                  currentMapRotationDegrees,
                ),
                child: Image.asset(
                  iconAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.directions_car,
                      color: fallbackColor,
                      size: 28,
                    );
                  },
                ),
              ),
            ),
          );
        })
        .toList();
  }

  Marker? get currentUserMarker {
    final location = currentUserLocation;

    if (location == null) {
      return null;
    }

    return Marker(
      point: location,
      width: 42,
      height: 42,
      rotate: true,
      child: Tooltip(
        message: 'Your location',
        child: Transform.rotate(
          angle: headingRadiansForMap(
            currentUserHeadingDegrees,
            currentMapRotationDegrees,
          ),
          child: CustomPaint(
            painter: CurrentUserTrianglePainter(),
            child: const SizedBox(width: 42, height: 42),
          ),
        ),
      ),
    );
  }

  void startPoliceReportSync() {
    policeReportSubscription?.cancel();
    policeReportSubscription = policeReportsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }

            final reports = snapshot.docs
                .map((doc) => PoliceReportData.fromFirestore(doc))
                .where((report) => report.isActive)
                .toList();

            setState(() {
              policeReports = reports;

              final selected = selectedPoliceReport;
              if (selected != null) {
                final stillVisible = reports.any(
                  (report) => report.id == selected.id,
                );
                if (!stillVisible) {
                  selectedPoliceReport = null;
                }
              }
            });
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  Future<void> showAddMapReportSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add map alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.local_police,
                      color: Colors.redAccent,
                    ),
                  ),
                  title: const Text(
                    'Police',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const Text(
                    'Mark police at your current location for 2 hours.',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'police'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == 'police') {
      await addPoliceReportAtCurrentLocation();
    }
  }

  double? policeReportDistanceMeters(PoliceReportData report) {
    final location = currentUserLocation;

    if (location == null) {
      return null;
    }

    return const Distance().as(LengthUnit.Meter, location, report.coordinates);
  }

  bool isPoliceReportCreatorCooldownOver(PoliceReportData report) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      report.createdAtMillis,
    );

    return DateTime.now().difference(createdAt) >=
        policeReportCreatorVoteCooldown;
  }

  bool canVotePoliceReportFromCurrentMapLocation(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return false;
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null || distance > policeReportVoteRadiusMeters) {
      return false;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return false;
    }

    return true;
  }

  String policeReportVoteHint(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return 'Log in to confirm this police mark.';
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null) {
      return 'Move to your current location before confirming this mark.';
    }

    if (distance > policeReportVoteRadiusMeters) {
      return 'Get closer to confirm this police mark.';
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return 'You created this mark. You can confirm it later if you drive by this spot again.';
    }

    return '';
  }

  Future<void> addPoliceReportAtCurrentLocation() async {
    if (isAddingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before adding a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isAddingPoliceReport = true);

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isAddingPoliceReport = false);
      return;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 2));
    final location = LatLng(position.latitude, position.longitude);
    final docRef = policeReportsCollection().doc();

    await docRef.set({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'stillThereBy': <String>[],
      'notThereBy': <String>[],
    });

    if (!mounted) {
      return;
    }

    final newReport = PoliceReportData(
      id: docRef.id,
      uid: firebaseUser.uid,
      username: currentUser.username,
      coordinates: location,
      createdAtMillis: now.millisecondsSinceEpoch,
      expiresAtMillis: expiresAt.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
    );

    setState(() {
      currentUserLocation = location;
      selectedSpot = null;
      selectedPoliceReport = newReport;
      isAddingPoliceReport = false;
    });

    mapController.move(location, 15.5);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: panel,
        content: Text(
          'Police marked on the map for 2 hours.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> votePoliceReport(
    PoliceReportData report, {
    required bool stillThere,
  }) async {
    if (isVotingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before confirming a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      return;
    }

    final freshLocation = LatLng(position.latitude, position.longitude);
    final distance = const Distance().as(
      LengthUnit.Meter,
      freshLocation,
      report.coordinates,
    );

    setState(() => currentUserLocation = freshLocation);

    if (distance > policeReportVoteRadiusMeters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: panel,
          content: Text(
            'Get closer to this police mark before confirming it.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: panel,
          content: Text(
            'You created this mark. You can confirm it later if you drive by this spot again.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isVotingPoliceReport = true);

    final reportRef = policeReportsCollection().doc(report.id);
    var removed = false;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(reportRef);

        if (!snapshot.exists) {
          removed = true;
          return;
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final stillThereBy = stringListFromFirebase(
          data['stillThereBy'],
          const [],
        );
        final notThereBy = stringListFromFirebase(data['notThereBy'], const []);

        stillThereBy.remove(firebaseUser.uid);
        notThereBy.remove(firebaseUser.uid);

        if (stillThere) {
          stillThereBy.add(firebaseUser.uid);
        } else {
          notThereBy.add(firebaseUser.uid);
        }

        final shouldRemove =
            !stillThere &&
            (notThereBy.length >= 2 || data['uid'] == firebaseUser.uid);

        if (shouldRemove) {
          removed = true;
          transaction.update(reportRef, {
            'status': 'removed',
            'removedByUid': firebaseUser.uid,
            'removedAt': FieldValue.serverTimestamp(),
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(reportRef, {
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } finally {
      if (mounted) {
        setState(() => isVotingPoliceReport = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (removed) {
      setState(() {
        selectedPoliceReport = null;
        policeReports = policeReports
            .where((item) => item.id != report.id)
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: panel,
          content: Text(
            'Police mark removed from the map.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: panel,
          content: Text(
            stillThere
                ? 'Thanks. Police mark confirmed.'
                : 'Thanks. Not there report saved.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  void startLiveLocationSync() {
    liveLocationSubscription?.cancel();
    liveLocationSubscription = liveLocationsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) {
              return;
            }

            final firebaseUser = FirebaseAuth.instance.currentUser;
            final locations = snapshot.docs
                .map((doc) => LiveLocationData.fromFirestore(doc))
                .where((location) => !location.isExpired)
                .toList();

            LiveLocationData? ownLocation;
            if (firebaseUser != null) {
              for (final location in locations) {
                if (location.uid == firebaseUser.uid) {
                  ownLocation = location;
                  break;
                }
              }
            }

            setState(() {
              liveLocations = locations;
              if (ownLocation != null) {
                isSharingLiveLocation = true;
                liveLocationPromptAt = DateTime.fromMillisecondsSinceEpoch(
                  ownLocation.promptAtMillis,
                );
                liveLocationExpiresAt = DateTime.fromMillisecondsSinceEpoch(
                  ownLocation.expiresAtMillis,
                );
                scheduleLiveLocationTimers();
              } else if (!isTogglingLiveLocation) {
                isSharingLiveLocation = false;
                liveLocationPromptAt = null;
                liveLocationExpiresAt = null;
                cancelLiveLocationTimers(keepUploadTimer: false);
              }
            });
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  void cancelLiveLocationTimers({bool keepUploadTimer = false}) {
    liveLocationPromptTimer?.cancel();
    liveLocationPromptTimer = null;
    liveLocationAutoStopTimer?.cancel();
    liveLocationAutoStopTimer = null;

    if (!keepUploadTimer) {
      liveLocationUploadTimer?.cancel();
      liveLocationUploadTimer = null;
    }
  }

  void scheduleLiveLocationTimers() {
    final promptAt = liveLocationPromptAt;
    final expiresAt = liveLocationExpiresAt;

    liveLocationPromptTimer?.cancel();
    liveLocationAutoStopTimer?.cancel();

    if (!isSharingLiveLocation || promptAt == null || expiresAt == null) {
      return;
    }

    final now = DateTime.now();
    final promptDelay = promptAt.difference(now);
    final autoStopDelay = expiresAt.difference(now);

    liveLocationPromptTimer = Timer(
      promptDelay.isNegative ? Duration.zero : promptDelay,
      showLiveLocationRenewPrompt,
    );
    liveLocationAutoStopTimer = Timer(
      autoStopDelay.isNegative ? Duration.zero : autoStopDelay,
      stopLiveLocationSharing,
    );
  }

  Future<void> toggleLiveLocationSharing(bool enabled) async {
    if (enabled) {
      await startLiveLocationSharing();
    } else {
      await stopLiveLocationSharing();
    }
  }

  Future<void> startLiveLocationSharing() async {
    if (isTogglingLiveLocation) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Log in before sharing your live location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isTogglingLiveLocation = true);

    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isTogglingLiveLocation = false);
      return;
    }

    final location = LatLng(position.latitude, position.longitude);
    final heading = headingForNewUserLocation(location, position.heading);

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      currentUserLocation = location;
      currentUserHeadingDegrees = heading;
      isSharingLiveLocation = true;
      isTogglingLiveLocation = false;
    });

    updateFollowCamera(location, heading);

    liveLocationUploadTimer?.cancel();
    liveLocationUploadTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => uploadLatestLiveLocation(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: panel,
        content: Text(
          'Live location sharing is on for 1 hour.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> uploadLatestLiveLocation() async {
    if (!isSharingLiveLocation) {
      return;
    }

    final position = await getMapUserPosition(showErrors: false);

    if (position == null || !mounted) {
      return;
    }

    final location = LatLng(position.latitude, position.longitude);
    final heading = headingForNewUserLocation(location, position.heading);

    await writeLiveLocation(
      position,
      renewWindow: false,
      headingDegrees: heading,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      currentUserLocation = location;
      currentUserHeadingDegrees = heading;
    });

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(location, heading);
    }
  }

  Future<void> writeLiveLocation(
    Position position, {
    required bool renewWindow,
    double? headingDegrees,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final now = DateTime.now();
    final promptAt = renewWindow
        ? now.add(const Duration(hours: 1))
        : liveLocationPromptAt ?? now.add(const Duration(hours: 1));
    final expiresAt = renewWindow
        ? promptAt.add(const Duration(minutes: 10))
        : liveLocationExpiresAt ?? promptAt.add(const Duration(minutes: 10));

    liveLocationPromptAt = promptAt;
    liveLocationExpiresAt = expiresAt;

    await liveLocationsCollection().doc(firebaseUser.uid).set({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'name': currentUser.name,
      'photoUrl': currentUser.photoUrl,
      'role': roleName(currentUser.role),
      'verified': currentUser.verified,
      'heading': normalizedHeadingDegrees(
        headingDegrees ?? position.heading,
        fallback: currentUserHeadingDegrees,
      ),
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'promptAt': Timestamp.fromDate(promptAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      scheduleLiveLocationTimers();
    }
  }

  Future<void> stopLiveLocationSharing() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    liveLocationUploadTimer?.cancel();
    liveLocationUploadTimer = null;
    cancelLiveLocationTimers(keepUploadTimer: true);

    if (firebaseUser != null) {
      await liveLocationsCollection().doc(firebaseUser.uid).delete();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isSharingLiveLocation = false;
      isTogglingLiveLocation = false;
      liveLocationPromptAt = null;
      liveLocationExpiresAt = null;
      liveLocationPromptOpen = false;
      liveLocations = liveLocations
          .where((location) => location.uid != firebaseUser?.uid)
          .toList();
    });
  }

  Future<void> continueLiveLocationSharing() async {
    final position = await getMapUserPosition(showErrors: true);

    if (!mounted) {
      return;
    }

    if (position == null) {
      await stopLiveLocationSharing();
      return;
    }

    final location = LatLng(position.latitude, position.longitude);
    final heading = headingForNewUserLocation(location, position.heading);

    await writeLiveLocation(
      position,
      renewWindow: true,
      headingDegrees: heading,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isSharingLiveLocation = true;
      currentUserLocation = location;
      currentUserHeadingDegrees = heading;
    });

    if (mapCenteredOnCurrentUser) {
      updateFollowCamera(location, heading);
    }
  }

  Future<void> showLiveLocationRenewPrompt() async {
    if (!mounted || !isSharingLiveLocation || liveLocationPromptOpen) {
      return;
    }

    liveLocationPromptOpen = true;

    final keepSharing = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'Continue sharing?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Your live location has been shared for 1 hour. Keep sharing it for another hour?',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stop sharing'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: blue),
              child: const Text(
                'Continue sharing',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    liveLocationPromptOpen = false;

    if (!mounted || !isSharingLiveLocation) {
      return;
    }

    if (keepSharing == true) {
      await continueLiveLocationSharing();
    } else if (keepSharing == false) {
      await stopLiveLocationSharing();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: panel,
          content: Text(
            'No answer. Live location will stop automatically in 10 minutes.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    temporarySpotRefreshTimer?.cancel();
    liveLocationUploadTimer?.cancel();
    liveLocationPromptTimer?.cancel();
    liveLocationAutoStopTimer?.cancel();
    liveLocationSubscription?.cancel();
    policeReportSubscription?.cancel();
    reviewSpots.removeListener(refreshMap);
    mapController.dispose();
    super.dispose();
  }

  void openSpotDetails(CarSpot spot) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
    );
  }

  void loadInitialUserLocation() {
    // Intentionally do nothing on map open.
    // The map should open on Riga spots first. User location is requested only
    // after pressing the blue "find me" button or enabling live location.
  }

  Future<Position?> getMapUserPosition({required bool showErrors}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Turn on phone location first.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Location permission is needed to show you on the map.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  double headingForNewUserLocation(LatLng nextLocation, double rawHeading) {
    final previousLocation = previousUserLocationForHeading ?? currentUserLocation;
    final normalizedRawHeading = normalizedHeadingDegrees(
      rawHeading,
      fallback: currentUserHeadingDegrees,
    );

    if (previousLocation == null) {
      previousUserLocationForHeading = nextLocation;
      return normalizedRawHeading;
    }

    final distanceMeters = distanceBetweenLatLngMeters(
      previousLocation,
      nextLocation,
    );

    previousUserLocationForHeading = nextLocation;

    // GPS heading is often 0 or frozen on some Android devices.
    // Bearing between the previous and new coordinates makes the car icon turn
    // correctly instead of visually driving sideways.
    if (distanceMeters >= 3) {
      return bearingBetweenLatLngDegrees(previousLocation, nextLocation);
    }

    return normalizedRawHeading;
  }

  void updateFollowCamera(LatLng location, double headingDegrees) {
    currentMapZoom = navigationZoom;
    currentMapRotationDegrees = headingDegrees;
    mapController.moveAndRotate(location, navigationZoom, headingDegrees);
  }

  Future<void> moveToCurrentLocation({bool showErrors = true}) async {
    if (isLocatingUser) {
      return;
    }

    setState(() => isLocatingUser = true);

    final position = await getMapUserPosition(showErrors: showErrors);

    if (!mounted) {
      return;
    }

    if (position == null) {
      setState(() => isLocatingUser = false);
      return;
    }

    final location = LatLng(position.latitude, position.longitude);
    final heading = headingForNewUserLocation(location, position.heading);

    setState(() {
      currentUserLocation = location;
      currentUserHeadingDegrees = heading;
      currentMapZoom = navigationZoom;
      currentMapRotationDegrees = heading;
      mapCenteredOnCurrentUser = true;
      selectedSpot = null;
      selectedPoliceReport = null;
      isLocatingUser = false;
    });

    updateFollowCamera(location, heading);
  }

  @override
  Widget build(BuildContext context) {
    final spot = selectedSpot;
    final policeReport = selectedPoliceReport;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: rigaCenter,
              initialZoom: rigaZoom,
              initialRotation: currentMapRotationDegrees,
              minZoom: 4,
              maxZoom: 18,
              backgroundColor: night,
              onPositionChanged: (camera, hasGesture) {
                final nextZoom = camera.zoom;
                final nextRotation = normalizedHeadingDegrees(
                  camera.rotation,
                  fallback: currentMapRotationDegrees,
                );
                final zoomChanged = (nextZoom - currentMapZoom).abs() >= 0.05;
                final rotationChanged =
                    (nextRotation - currentMapRotationDegrees).abs() >= 0.5;

                if (zoomChanged || rotationChanged || hasGesture) {
                  setState(() {
                    currentMapZoom = nextZoom;
                    currentMapRotationDegrees = nextRotation;
                    if (hasGesture) {
                      mapCenteredOnCurrentUser = false;
                    }
                  });
                }
              },
              onTap: (_, _) => setState(() {
                selectedSpot = null;
                selectedPoliceReport = null;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ccs_app',
                maxNativeZoom: 19,
              ),
              MarkerLayer(markers: allMapMarkers),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: _MapHeader(
                    approvedCount: visibleSpots.length,
                    isSharingLiveLocation: isSharingLiveLocation,
                    isBusy: isTogglingLiveLocation,
                    onShareChanged: toggleLiveLocationSharing,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MapFilterButton(
                      enabledCount: enabledCategoryFilters.length,
                      totalCount: spotCategoryOptions.length,
                      onTap: showMapCategoryFilterSheet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: spot == null && policeReport == null ? 18 : 196,
            child: FloatingActionButton.small(
              heroTag: 'add_map_report',
              onPressed: isAddingPoliceReport ? null : showAddMapReportSheet,
              backgroundColor: panel,
              foregroundColor: Colors.white,
              child: isAddingPoliceReport
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
            ),
          ),
          Positioned(
            right: 16,
            bottom: spot == null && policeReport == null ? 18 : 196,
            child: FloatingActionButton.small(
              heroTag: 'current_location',
              onPressed: isLocatingUser ? null : () => moveToCurrentLocation(),
              backgroundColor: blue,
              foregroundColor: Colors.white,
              child: isLocatingUser
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          if (policeReport != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: PoliceReportMapCard(
                report: policeReport,
                isBusy: isVotingPoliceReport,
                canVote: canVotePoliceReportFromCurrentMapLocation(
                  policeReport,
                ),
                voteHint: policeReportVoteHint(policeReport),
                onStillThere: () =>
                    votePoliceReport(policeReport, stillThere: true),
                onNotThere: () =>
                    votePoliceReport(policeReport, stillThere: false),
              ),
            ),
          if (spot != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SpotMapCard(
                spot: spot,
                onOpen: () => openSpotDetails(spot),
              ),
            ),
        ],
      ),
    );
  }
}

class MapFilterButton extends StatelessWidget {
  final int enabledCount;
  final int totalCount;
  final VoidCallback onTap;

  const MapFilterButton({
    super.key,
    required this.enabledCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allEnabled = enabledCount == totalCount;
    final label = allEnabled ? 'Filters' : 'Filters $enabledCount/$totalCount';

    return Material(
      color: panel.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: allEnabled ? Colors.white12 : blue.withValues(alpha: 0.75),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                color: allEnabled ? Colors.white70 : blue,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactSpotMapPoint extends StatelessWidget {
  final Color color;

  const CompactSpotMapPoint({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.80),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  final int approvedCount;
  final bool isSharingLiveLocation;
  final bool isBusy;
  final ValueChanged<bool> onShareChanged;

  const _MapHeader({
    required this.approvedCount,
    required this.isSharingLiveLocation,
    required this.isBusy,
    required this.onShareChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.map, color: blue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CCS Map',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Approved Riga car spots',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '$approvedCount spots',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  color: isSharingLiveLocation
                      ? blue.withValues(alpha: 0.18)
                      : panel.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSharingLiveLocation ? blue : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Share live location',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.74,
                      child: Switch(
                        value: isSharingLiveLocation,
                        activeThumbColor: blue,
                        onChanged: isBusy ? null : onShareChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

  const PoliceReportMapCard({
    super.key,
    required this.report,
    required this.isBusy,
    required this.canVote,
    required this.voteHint,
    required this.onStillThere,
    required this.onNotThere,
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
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_police, color: Colors.redAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
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
                      child: Text(
                        'Marked by @${report.username} - $timeLeftLabel',
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
              _SmallTag(
                label: '${report.stillThereCount} still there',
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _SmallTag(
                label: '${report.notThereCount} not there',
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!canVote)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
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
                    label: const Text('Not there'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : onStillThere,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Still there'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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

class SpotMapCard extends StatelessWidget {
  final CarSpot spot;
  final VoidCallback onOpen;

  const SpotMapCard({super.key, required this.spot, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SpotPhoto(
              spot: spot,
              width: 96,
              height: 124,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: blue, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      spot.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  spot.cityCountry,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  spot.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (spot.isTemporary)
                      _SmallTag(
                        label: spot.temporaryTimeLabel,
                        icon: Icons.event,
                      ),
                    _SmallTag(label: spot.bestTime, icon: Icons.dark_mode),
                    _SmallTag(
                      label: spot.lowCarFriendly ? 'Low car OK' : 'Careful',
                      icon: Icons.speed,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          onPressed: onOpen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_full, size: 16),
                              SizedBox(width: 8),
                              Text('View Spot'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SaveSpotButton(spot: spot, compact: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SaveSpotButton extends StatelessWidget {
  final CarSpot spot;
  final bool compact;

  const SaveSpotButton({super.key, required this.spot, this.compact = false});

  bool isSaved(List<CarSpot> spots) {
    return spots.any((savedSpot) => savedSpot.name == spot.name);
  }

  void toggleSaved(BuildContext context, bool saved) {
    if (saved) {
      savedSpots.value = savedSpots.value
          .where((savedSpot) => savedSpot.name != spot.name)
          .toList();
    } else {
      savedSpots.value = [spot, ...savedSpots.value];
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: saved ? panel : blue,
        content: Text(
          saved ? 'Spot removed from saved.' : 'Spot saved.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: savedSpots,
      builder: (context, spots, _) {
        final saved = isSaved(spots);

        if (compact) {
          return SizedBox(
            width: 46,
            height: 38,
            child: OutlinedButton(
              onPressed: () => toggleSaved(context, saved),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: saved ? blue : Colors.white,
                side: BorderSide(color: saved ? blue : Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => toggleSaved(context, saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            label: Text(saved ? 'Saved Spot' : 'Save Spot'),
            style: OutlinedButton.styleFrom(
              foregroundColor: saved ? blue : Colors.white,
              side: BorderSide(color: saved ? blue : Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SavedSpotTile extends StatelessWidget {
  final CarSpot spot;

  const SavedSpotTile({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 84,
              height: 84,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in spot.categories.take(2))
                        _SmallTag(label: category, icon: Icons.local_offer),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: blue),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
        ],
      ),
    );
  }
}

Future<void> launchExternalUrl(BuildContext context, String rawUrl) async {
  final trimmedUrl = rawUrl.trim();

  if (trimmedUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'No link added for this spot.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(trimmedUrl);

  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'This link is not valid yet.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open this link.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Future<void> openWazeRoute(BuildContext context, CarSpot spot) async {
  final lat = spot.coordinates.latitude;
  final lng = spot.coordinates.longitude;
  final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
  final webUri = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');

  try {
    final openedWaze = await launchUrl(
      wazeUri,
      mode: LaunchMode.externalApplication,
    );

    if (openedWaze) {
      return;
    }

    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}

Future<Position?> getCurrentPhoneLocation(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Turn on phone location to show distance.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Location permission is needed for distance.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
  );
}

double distanceToSpotInKm(Position position, CarSpot spot) {
  const distance = Distance();

  return distance.as(
    LengthUnit.Kilometer,
    LatLng(position.latitude, position.longitude),
    spot.coordinates,
  );
}

String formatDistanceKm(double value) {
  if (value < 1) {
    return '${(value * 1000).round()} m';
  }

  return '${value.toStringAsFixed(1)} km';
}

String estimateDriveTime(double distanceKm) {
  // This is only a rough straight-line estimate before Waze opens.
  // City trips use slower speed, long trips use a higher average speed.
  final averageSpeedKmh = distanceKm > 120 ? 70 : 35;
  final minutes = (distanceKm / averageSpeedKmh * 60).round().clamp(2, 999999);

  if (minutes < 60) {
    return '~$minutes min';
  }

  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;

  if (hours < 24) {
    return restMinutes == 0 ? '~$hours h' : '~$hours h $restMinutes min';
  }

  final days = hours ~/ 24;
  final restHours = hours % 24;

  return restHours == 0 ? '~$days d' : '~$days d $restHours h';
}

List<String> spotPhotoSources(CarSpot spot) {
  final sources = <String>[];

  void addSource(String value) {
    final trimmed = value.trim();

    if (trimmed.isNotEmpty && !sources.contains(trimmed)) {
      sources.add(trimmed);
    }
  }

  if (localFileExists(spot.localPhotoPath)) {
    addSource('local:${spot.localPhotoPath}');
  }

  for (final photoUrl in spot.photoUrls) {
    addSource(photoUrl);
  }

  addSource(spot.photoUrl);

  return sources;
}

bool isLocalSpotPhotoSource(String source) {
  return source.startsWith('local:');
}

String localPhotoPathFromSource(String source) {
  return source.substring('local:'.length);
}

Widget spotPhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (isLocalSpotPhotoSource(source)) {
    return Image.file(
      File(localPhotoPathFromSource(source)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          _SpotPhotoPlaceholder(width: width, height: height),
    );
  }

  return Image.network(
    source,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, _, _) =>
        _SpotPhotoPlaceholder(width: width, height: height),
  );
}

class SpotPhotoCarousel extends StatefulWidget {
  final CarSpot spot;
  final double height;

  const SpotPhotoCarousel({
    super.key,
    required this.spot,
    required this.height,
  });

  @override
  State<SpotPhotoCarousel> createState() => _SpotPhotoCarouselState();
}

class _SpotPhotoCarouselState extends State<SpotPhotoCarousel> {
  int currentIndex = 0;

  void openGallery(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SpotPhotoGalleryScreen(spot: widget.spot, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = spotPhotoSources(widget.spot);

    if (sources.isEmpty) {
      return _SpotPhotoPlaceholder(height: widget.height);
    }

    if (currentIndex >= sources.length) {
      currentIndex = sources.length - 1;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => openGallery(currentIndex),
                child: spotPhotoImage(
                  sources[currentIndex],
                  width: double.infinity,
                  height: widget.height,
                  fit: BoxFit.cover,
                ),
              ),
              if (sources.length > 1)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${currentIndex + 1}/${sources.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (sources.length > 1)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: Colors.black,
            child: Row(
              children: [
                for (var index = 0; index < sources.length; index++) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => currentIndex = index),
                      onLongPress: () => openGallery(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: currentIndex == index ? blue : Colors.white24,
                            width: currentIndex == index ? 2.2 : 1,
                          ),
                          boxShadow: currentIndex == index
                              ? [
                                  BoxShadow(
                                    color: blue.withValues(alpha: 0.36),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            spotPhotoImage(
                              sources[index],
                              fit: BoxFit.cover,
                            ),
                            if (currentIndex == index)
                              Container(
                                decoration: BoxDecoration(
                                  color: blue.withValues(alpha: 0.16),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index != sources.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class SpotPhotoGalleryScreen extends StatefulWidget {
  final CarSpot spot;
  final int initialIndex;

  const SpotPhotoGalleryScreen({
    super.key,
    required this.spot,
    required this.initialIndex,
  });

  @override
  State<SpotPhotoGalleryScreen> createState() => _SpotPhotoGalleryScreenState();
}

class _SpotPhotoGalleryScreenState extends State<SpotPhotoGalleryScreen> {
  late final List<String> sources;
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    sources = spotPhotoSources(widget.spot);
    currentIndex =
        widget.initialIndex >= 0 && widget.initialIndex < sources.length
        ? widget.initialIndex
        : 0;
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (sources.isEmpty)
            const Center(
              child: Icon(Icons.directions_car, color: blue, size: 44),
            )
          else
            PageView.builder(
              controller: controller,
              itemCount: sources.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: spotPhotoImage(
                      sources[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (sources.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${currentIndex + 1}/${sources.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotDetailScreen extends StatefulWidget {
  final CarSpot spot;

  const SpotDetailScreen({super.key, required this.spot});

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  late CarSpot spot;

  @override
  void initState() {
    super.initState();
    spot = widget.spot;
  }

  void updateVisibleRating(double rating) {
    if ((spot.rating - rating).abs() < 0.01) {
      return;
    }

    setState(() => spot = spot.copyWith(rating: rating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Spot'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        children: [
          SpotPhotoCarousel(spot: spot, height: 300),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        spot.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (spot.hasOwner) ...[
                      const SizedBox(width: 10),
                      SpotOwnerBadge(spot: spot),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  spot.cityCountry,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 18),
                SpotDetailEngagementPanel(
                  spot: spot,
                  onRatingChanged: updateVisibleRating,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (spot.createdAtMillis > 0) ...[
                      Icon(
                        Icons.schedule,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Added ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(spot.createdAtMillis))}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: spot.addedByUid.trim().isEmpty
                          ? Text(
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Added by @${spot.addedBy.replaceAll('@', '')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: blue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  spot.description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (spot.isTemporary)
                      _SmallTag(
                        label: spot.temporaryTimeLabel,
                        icon: Icons.event,
                      ),
                    for (final category in spot.categories)
                      _SmallTag(label: category, icon: Icons.local_offer),
                  ],
                ),
                const SizedBox(height: 22),
                SaveSpotButton(spot: spot),
                const SizedBox(height: 12),
                SpotRouteActions(spot: spot),
                if (spot.supportsContacts) ...[
                  const SizedBox(height: 24),
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
                          MaterialPageRoute(
                            builder: (_) =>
                                ServiceSpotBusinessEditScreen(spot: spot),
                          ),
                        );

                        if (updatedSpot != null && mounted) {
                          setState(() => spot = updatedSpot);
                        }
                      },
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Service Info'),
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
                  const SizedBox(height: 24),
                  SpotContactSection(spot: spot),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Video link',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => launchExternalUrl(context, spot.reelLink),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            spot.reelLink.isEmpty
                                ? 'No video link added'
                                : spot.reelLink,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.open_in_new, color: blue, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SpotReviewsSection(spot: spot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotOwnerBadge extends StatelessWidget {
  final CarSpot spot;

  const SpotOwnerBadge({super.key, required this.spot});

  String get ownerLabel {
    final username = spot.ownerUsername.trim();

    if (username.isNotEmpty) {
      final handle = username.startsWith('@') ? username : '@$username';
      return 'Owner $handle';
    }

    return 'Owner';
  }

  @override
  Widget build(BuildContext context) {
    final badge = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: blue.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_accounts, color: blue, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                ownerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (spot.ownerUid.trim().isEmpty) {
      return badge;
    }

    return InkWell(
      onTap: () => openUserProfile(
        context,
        uid: spot.ownerUid,
        fallbackUsername: spot.ownerUsername,
      ),
      borderRadius: BorderRadius.circular(999),
      child: badge,
    );
  }
}

Future<void> launchContactUri(BuildContext context, Uri uri) async {
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Could not open this contact.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Uri instagramContactUri(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);

  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }

  var handle = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  handle = handle.replaceFirst(RegExp(r'^(www\.)?instagram\.com/?'), '');
  handle = handle.replaceAll(RegExp(r'^/+'), '');

  return Uri.https('instagram.com', handle.isEmpty ? '/' : '/$handle');
}

class SpotBusinessStatus {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const SpotBusinessStatus({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

String nextOpeningLabel(Map<int, OpeningHoursData> openingHours, int weekday) {
  for (var offset = 1; offset <= 7; offset++) {
    final nextWeekday = ((weekday - 1 + offset) % 7) + 1;
    final nextDay = openingHours[nextWeekday];
    if (nextDay != null && nextDay.isOpen) {
      return '${weekdayLabels[nextWeekday] ?? 'Next day'} at ${nextDay.opensAt}';
    }
  }

  return 'No upcoming opening hours';
}

SpotBusinessStatus businessStatusForSpot(CarSpot spot) {
  if (spot.openingHours.isEmpty) {
    return const SpotBusinessStatus(
      title: 'Hours not added',
      subtitle: 'The owner has not added opening hours yet.',
      icon: Icons.schedule,
      color: Colors.white54,
    );
  }

  final now = DateTime.now();
  final today = spot.openingHours[now.weekday];
  final weekdayName = weekdayLabels[now.weekday] ?? 'Today';

  if (today == null || !today.isOpen) {
    return SpotBusinessStatus(
      title: 'Closed today',
      subtitle: '$weekdayName is marked as closed.',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  final opensAt = minutesFromClockText(today.opensAt);
  final closesAt = minutesFromClockText(today.closesAt);
  final nowMinutes = now.hour * 60 + now.minute;

  if (opensAt == null || closesAt == null) {
    return const SpotBusinessStatus(
      title: 'Hours need update',
      subtitle: 'Opening hours are not formatted correctly.',
      icon: Icons.error_outline,
      color: Colors.orangeAccent,
    );
  }

  final isOpenNow = closesAt > opensAt
      ? nowMinutes >= opensAt && nowMinutes < closesAt
      : nowMinutes >= opensAt || nowMinutes < closesAt;

  if (isOpenNow) {
    return SpotBusinessStatus(
      title: 'Open now',
      subtitle: 'Today ${today.opensAt} - ${today.closesAt}',
      icon: Icons.check,
      color: Colors.greenAccent,
    );
  }

  if (closesAt > opensAt && nowMinutes < opensAt) {
    return SpotBusinessStatus(
      title: 'Closed now',
      subtitle: 'Opens today at ${today.opensAt}',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  return SpotBusinessStatus(
    title: 'Closed now',
    subtitle: 'Opens ${nextOpeningLabel(spot.openingHours, now.weekday)}',
    icon: Icons.close,
    color: Colors.redAccent,
  );
}

bool spotIsClosedNow(CarSpot spot) {
  if (!spot.supportsContacts || !spot.hasOpeningHours) {
    return false;
  }

  final status = businessStatusForSpot(spot);
  return status.title == 'Closed now' || status.title == 'Closed today';
}

class SpotBusinessStatusCard extends StatelessWidget {
  final CarSpot spot;

  const SpotBusinessStatusCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final status = businessStatusForSpot(spot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(status.icon, color: status.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status.subtitle,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotContactSection extends StatelessWidget {
  final CarSpot spot;

  const SpotContactSection({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contacts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              if (spot.contactPhone.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.phone,
                  label: 'Phone',
                  value: spot.contactPhone,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'tel', path: spot.contactPhone.trim()),
                  ),
                ),
              if (spot.contactInstagram.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.alternate_email,
                  label: 'Instagram',
                  value: spot.contactInstagram,
                  onTap: () => launchContactUri(
                    context,
                    instagramContactUri(spot.contactInstagram),
                  ),
                ),
              if (spot.contactEmail.trim().isNotEmpty)
                _SpotContactTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: spot.contactEmail,
                  onTap: () => launchContactUri(
                    context,
                    Uri(scheme: 'mailto', path: spot.contactEmail.trim()),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SpotContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

class SpotDetailEngagementPanel extends StatefulWidget {
  final CarSpot spot;
  final ValueChanged<double>? onRatingChanged;

  const SpotDetailEngagementPanel({
    super.key,
    required this.spot,
    this.onRatingChanged,
  });

  @override
  State<SpotDetailEngagementPanel> createState() =>
      _SpotDetailEngagementPanelState();
}

class _SpotDetailEngagementPanelState extends State<SpotDetailEngagementPanel> {
  bool isSavingRating = false;

  Future<void> submitRating(int rating) async {
    setState(() => isSavingRating = true);

    try {
      final updatedRating = await saveSpotRating(
        spot: widget.spot,
        rating: rating,
      );

      if (!mounted) {
        return;
      }

      if (updatedRating != null) {
        widget.onRatingChanged?.call(updatedRating);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Rating saved.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final code = error is FirebaseException ? error.code : error.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save rating: $code',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSavingRating = false);
      }
    }
  }

  Widget starButton(int value, int currentRating) {
    final selected = value <= currentRating;

    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: isSavingRating ? null : () => submitRating(value),
      icon: Icon(
        selected ? Icons.star : Icons.star_border,
        color: selected ? blue : Colors.white38,
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: blue, size: 19),
              const SizedBox(width: 7),
              Text(
                '${widget.spot.rating.toStringAsFixed(1)} spot rating',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              StreamBuilder<bool>(
                stream: watchCurrentUserLikedSpot(widget.spot),
                builder: (context, likedSnapshot) {
                  final liked = likedSnapshot.data ?? false;

                  return StreamBuilder<int>(
                    stream: watchSpotLikeCount(widget.spot),
                    builder: (context, countSnapshot) {
                      final likeCount = countSnapshot.data ?? 0;

                      return InkWell(
                        onTap: () =>
                            toggleSpotLike(context, widget.spot, liked),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: liked
                                ? Colors.redAccent.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: liked ? Colors.redAccent : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked ? Icons.favorite : Icons.favorite_border,
                                color: liked
                                    ? Colors.redAccent
                                    : Colors.white70,
                                size: 23,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                liked ? 'Liked' : 'Like',
                                style: TextStyle(
                                  color: liked
                                      ? Colors.redAccent
                                      : Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$likeCount',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your rating',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          StreamBuilder<int>(
            stream: watchCurrentUserSpotRating(widget.spot),
            builder: (context, ratingSnapshot) {
              final currentRating = ratingSnapshot.data ?? 0;

              return Row(
                children: [
                  for (var i = 1; i <= 5; i++) starButton(i, currentRating),
                  if (isSavingRating) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class SpotRouteActions extends StatefulWidget {
  final CarSpot spot;

  const SpotRouteActions({super.key, required this.spot});

  @override
  State<SpotRouteActions> createState() => _SpotRouteActionsState();
}

class _SpotRouteActionsState extends State<SpotRouteActions> {
  bool isLoadingDistance = false;
  double? distanceKm;

  @override
  void initState() {
    super.initState();
    loadDistance();
  }

  Future<void> loadDistance() async {
    if (isLoadingDistance) {
      return;
    }

    setState(() => isLoadingDistance = true);

    final position = await getCurrentPhoneLocation(context);

    if (!mounted) {
      return;
    }

    setState(() {
      distanceKm = position == null
          ? null
          : distanceToSpotInKm(position, widget.spot);
      isLoadingDistance = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm == null
        ? (isLoadingDistance ? 'Checking distance...' : 'Distance unavailable')
        : '${formatDistanceKm(distanceKm!)} away';
    final timeText = distanceKm == null
        ? 'Open route'
        : estimateDriveTime(distanceKm!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.route, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distanceText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(timeText, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => openWazeRoute(context, widget.spot),
              icon: const Icon(Icons.navigation, size: 17),
              label: const Text('Waze'),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotReviewsSection extends StatefulWidget {
  final CarSpot spot;

  const SpotReviewsSection({super.key, required this.spot});

  @override
  State<SpotReviewsSection> createState() => _SpotReviewsSectionState();
}

class _SpotReviewsSectionState extends State<SpotReviewsSection> {
  final commentController = TextEditingController();
  bool isSaving = false;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> submitComment() async {
    final comment = commentController.text.trim();

    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Write a comment first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      await saveSpotReview(spot: widget.spot, comment: comment);

      if (!mounted) {
        return;
      }

      commentController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Comment posted.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final code = error is FirebaseException ? error.code : error.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save comment: $code',
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
    return StreamBuilder<List<SpotReviewData>>(
      stream: watchSpotReviews(widget.spot),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <SpotReviewData>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  reviews.isEmpty
                      ? '0 comments'
                      : '${reviews.length} ${reviews.length == 1 ? 'comment' : 'comments'}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: commentController,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Write a comment about this spot',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : submitComment,
                      icon: Icon(
                        isSaving ? Icons.hourglass_bottom : Icons.send,
                      ),
                      label: Text(isSaving ? 'Saving...' : 'Post Comment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  'No comments yet. Be the first to comment on this spot.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              for (final review in reviews) ...[
                SpotReviewCard(spot: widget.spot, review: review),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class SpotReviewCard extends StatelessWidget {
  final CarSpot spot;
  final SpotReviewData review;

  const SpotReviewCard({super.key, required this.spot, required this.review});

  Future<void> _showEditDialog(BuildContext context) async {
    final commentController = TextEditingController(text: review.comment);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'Edit comment',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: commentController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Edit your comment',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (commentController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      return;
    }

    final newComment = commentController.text.trim();

    try {
      await editSpotReview(spot: spot, review: review, comment: newComment);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Comment updated.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'Delete comment',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to delete this comment?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await deleteSpotReview(spot: spot, review: review);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'Comment deleted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final code = error is FirebaseException ? error.code : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not delete comment: $code',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = FirebaseAuth.instance.currentUser?.uid == review.userId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: review.userId.trim().isEmpty
                      ? null
                      : () => openUserProfile(
                            context,
                            uid: review.userId,
                            fallbackUsername: review.username,
                          ),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '@${review.username.replaceAll('@', '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                formatShortDate(review.createdAt),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: watchCurrentUserLikedComment(review),
                builder: (context, likedSnapshot) {
                  final liked = likedSnapshot.data ?? false;

                  return StreamBuilder<int>(
                    stream: watchCommentLikeCount(review),
                    builder: (context, countSnapshot) {
                      final likeCount = countSnapshot.data ?? 0;

                      return InkWell(
                        onTap: () => toggleCommentLike(context, review, liked),
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked ? Icons.favorite : Icons.favorite_border,
                                color: liked
                                    ? Colors.redAccent
                                    : Colors.white54,
                                size: 17,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$likeCount',
                                style: TextStyle(
                                  color: liked
                                      ? Colors.redAccent
                                      : Colors.white54,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const Spacer(),
              if (canManage) ...[
                IconButton(
                  onPressed: () => _showEditDialog(context),
                  icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                  tooltip: 'Edit comment',
                ),
                IconButton(
                  onPressed: () => _showDeleteDialog(context),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.white54,
                    size: 18,
                  ),
                  tooltip: 'Delete comment',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SpotPhoto extends StatelessWidget {
  final CarSpot spot;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SpotPhoto({
    super.key,
    required this.spot,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final sources = spotPhotoSources(spot);
    final photo = sources.isEmpty
        ? _SpotPhotoPlaceholder(width: width, height: height)
        : spotPhotoImage(sources.first, width: width, height: height, fit: fit);

    if (borderRadius == null) {
      return photo;
    }

    return ClipRRect(borderRadius: borderRadius!, child: photo);
  }
}

class _SpotPhotoPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;

  const _SpotPhotoPlaceholder({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue),
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SmallTag({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: blue, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCategoryDropdown extends StatelessWidget {
  final String value;
  final List<String> categories;
  final ValueChanged<String?> onChanged;

  const _SpotCategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: panel,
      iconEnabledColor: blue,
      decoration: InputDecoration(
        labelText: 'Category',
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            spotIconAssetPathForCategory(value),
            width: 24,
            height: 24,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.local_offer, color: blue),
          ),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      items: categories.map((category) {
        return DropdownMenuItem<String>(
          value: category,
          child: Row(
            children: [
              Image.asset(
                spotIconAssetPathForCategory(category),
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.local_offer, color: blue, size: 20),
              ),
              const SizedBox(width: 10),
              Text(category),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class AddSpotScreen extends StatefulWidget {
  const AddSpotScreen({super.key});

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen> {
  final nameController = TextEditingController();
  final cityController = TextEditingController();
  final addressController = TextEditingController();
  final descriptionController = TextEditingController();
  final reelController = TextEditingController();
  final phoneController = TextEditingController();
  final instagramController = TextEditingController();
  final emailController = TextEditingController();
  final addedByController = TextEditingController();

  final categoryOptions = spotCategoryOptions;

  String selectedCategory = 'Photo';
  LatLng? selectedLocation;
  String detectedCityCountry = 'Choose location to detect city/country';
  bool isDetectingCityCountry = false;
  final List<String> selectedPhotoPaths = [];
  bool verifiedOnlySpot = false;
  bool isTemporarySpot = false;
  DateTime? temporaryStartsAt;
  DateTime? temporaryExpiresAt;
  Map<int, OpeningHoursData> openingHours = defaultServiceOpeningHours();
  SpotOwnerAssignment? selectedOwner;
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    addedByController.text = currentUser.username;
  }

  @override
  void dispose() {
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

  Future<void> applySelectedLocation(LatLng location) async {
    setState(() {
      selectedLocation = location;
      detectedCityCountry = 'Detecting city/country...';
      isDetectingCityCountry = true;
    });

    final cityCountry = await detectCityCountryForCoordinates(location);

    if (!mounted) {
      return;
    }

    setState(() {
      detectedCityCountry = cityCountry;
      isDetectingCityCountry = false;
    });
  }

  Future<void> chooseLocation() async {
    FocusScope.of(context).unfocus();

    final location = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLocation: selectedLocation),
      ),
    );

    if (!mounted || location == null) {
      return;
    }

    await applySelectedLocation(location);
  }

  Future<void> findExactAddress() async {
    FocusScope.of(context).unfocus();

    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text('Find exact address'),
          content: TextField(
            controller: addressController,
            autofocus: true,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Street, city, country',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: blue),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: blue),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, addressController.text.trim()),
              child: const Text('Find'),
            ),
          ],
        );
      },
    );

    if (!mounted || address == null || address.trim().isEmpty) {
      return;
    }

    try {
      setState(() {
        detectedCityCountry = 'Finding address...';
        isDetectingCityCountry = true;
      });

      final locations = await locationFromAddress(address.trim());

      if (!mounted) {
        return;
      }

      if (locations.isEmpty) {
        setState(() {
          detectedCityCountry = selectedLocation == null
              ? 'Choose location to detect city/country'
              : detectedCityCountry;
          isDetectingCityCountry = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Address not found. Try adding city and country.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final first = locations.first;
      await applySelectedLocation(LatLng(first.latitude, first.longitude));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        detectedCityCountry = selectedLocation == null
            ? 'Choose location to detect city/country'
            : detectedCityCountry;
        isDetectingCityCountry = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not find that address. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> choosePhoto() async {
    FocusScope.of(context).unfocus();

    if (selectedPhotoPaths.length >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Maximum 4 photos per spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(context);

    if (!mounted || path == null) {
      return;
    }

    if (selectedPhotoPaths.contains(path)) {
      return;
    }

    setState(() => selectedPhotoPaths.add(path));
  }

  void removePhotoAt(int index) {
    if (index < 0 || index >= selectedPhotoPaths.length) {
      return;
    }

    setState(() => selectedPhotoPaths.removeAt(index));
  }

  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue) async {
    final now = DateTime.now();
    final initial = initialValue ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> chooseTemporaryStart() async {
    final value = await pickTemporaryDateTime(temporaryStartsAt);

    if (!mounted || value == null) {
      return;
    }

    setState(() {
      temporaryStartsAt = value;
      if (temporaryExpiresAt == null || !temporaryExpiresAt!.isAfter(value)) {
        temporaryExpiresAt = value.add(const Duration(hours: 3));
      }
    });
  }

  Future<void> chooseTemporaryEnd() async {
    final fallback = temporaryStartsAt?.add(const Duration(hours: 3));
    final value = await pickTemporaryDateTime(temporaryExpiresAt ?? fallback);

    if (!mounted || value == null) {
      return;
    }

    setState(() => temporaryExpiresAt = value);
  }

  Future<void> submitSpot() async {
    FocusScope.of(context).unfocus();

    if (isSubmitting) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Sign in with Google before submitting a spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Choose the spot location on the map or find exact address first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isTemporarySpot) {
      final startsAt = temporaryStartsAt;
      final expiresAt = temporaryExpiresAt;

      if (startsAt == null || expiresAt == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Choose both start and end time for a temporary spot.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!expiresAt.isAfter(startsAt)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'End time must be after start time.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!expiresAt.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'End time must be in the future.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }
    }

    final location = selectedLocation!;
    final categories = [selectedCategory];
    final supportsContacts = spotCategorySupportsContacts(selectedCategory);
    final owner =
        supportsContacts && currentUser.role == UserRole.admin
        ? selectedOwner
        : null;

    final isAdminCreatedSpot = currentUser.role == UserRole.admin;
    final initialStatus = isAdminCreatedSpot
        ? SpotStatus.approved
        : SpotStatus.pending;
    final spotRef = spotsCollection().doc();

    var newSpot = CarSpot(
      id: spotRef.id,
      name: nameController.text.trim().isEmpty
          ? 'Untitled spot'
          : nameController.text.trim(),
      cityCountry:
          detectedCityCountry.trim().isEmpty ||
              detectedCityCountry == 'Choose location to detect city/country' ||
              detectedCityCountry == 'Detecting city/country...'
          ? 'Unknown location'
          : detectedCityCountry.trim(),
      coordinates: location,
      description: descriptionController.text.trim().isEmpty
          ? 'Submitted community car spot.'
          : descriptionController.text.trim(),
      categories: categories,
      rating: isAdminCreatedSpot ? 4.5 : 0,
      photoUrl: '',
      localPhotoPath: selectedPhotoPaths.isEmpty ? null : selectedPhotoPaths.first,
      reelLink: reelController.text.trim(),
      contactPhone: supportsContacts ? phoneController.text.trim() : '',
      contactInstagram: supportsContacts ? instagramController.text.trim() : '',
      contactEmail: supportsContacts ? emailController.text.trim() : '',
      openingHours: supportsContacts ? openingHours : const {},
      ownerUid: supportsContacts ? (owner?.uid ?? '') : '',
      ownerUsername: supportsContacts ? (owner?.username ?? '') : '',
      bestTime: 'Not reviewed',
      parking: 'Not reviewed',
      roadQuality: 'Not reviewed',
      lowCarFriendly: false,
      policeRisk: 'Not reviewed',
      traffic: 'Not reviewed',
      lighting: 'Not reviewed',
      crowd: 'Not reviewed',
      addedBy: currentUser.username,
      addedByUid: firebaseUser.uid,
      status: initialStatus,
      isTemporary: isTemporarySpot,
      startsAtMillis: isTemporarySpot
          ? temporaryStartsAt!.millisecondsSinceEpoch
          : null,
      expiresAtMillis: isTemporarySpot
          ? temporaryExpiresAt!.millisecondsSinceEpoch
          : null,
      verifiedOnly: verifiedOnlySpot,
    );

    setState(() => isSubmitting = true);

    try {
      final uploadedPhotoUrls = <String>[];

      for (var index = 0; index < selectedPhotoPaths.length; index++) {
        final uploadedUrl = await uploadSpotPhoto(
          spotId: spotRef.id,
          localPhotoPath: selectedPhotoPaths[index],
          userId: firebaseUser.uid,
          photoIndex: index,
        );
        uploadedPhotoUrls.add(uploadedUrl);
      }

      newSpot = newSpot.copyWith(
        photoUrl: uploadedPhotoUrls.isEmpty ? '' : uploadedPhotoUrls.first,
        photoUrls: uploadedPhotoUrls,
      );
      await spotRef.set(spotToFirestoreData(newSpot, includeCreatedAt: true));

      if (isAdminCreatedSpot && newSpot.categories.contains('Meet')) {
        await createMeetSpotNotificationsForNearbyUsers(newSpot);
      }

      if (!isAdminCreatedSpot) {
        await createAdminSpotReviewNotification(newSpot);
      }

      final savedSpot = await spotRef.get(
        const GetOptions(source: Source.server),
      );

      if (!savedSpot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'spot-not-found-after-save',
          message: 'Firebase did not return the saved spot.',
        );
      }

      await refreshFirebaseSpotsFromServer();

      if (!mounted) {
        return;
      }

      final message = isAdminCreatedSpot
          ? 'Admin spot added. It is live now.'
          : 'Spot submitted for review. Admins have been notified.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Firebase did not save the spot/photo: ${error.code}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCS'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add_location_alt, color: blue),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Spot',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Admins publish instantly. User spots wait for review.',
                        style: TextStyle(color: Colors.white54, height: 1.3),
                      ),
                    ],
                  ),
                ),
                _PendingBadge(
                  status: currentUser.role == UserRole.admin
                      ? SpotStatus.approved
                      : SpotStatus.pending,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AddSpotSection(
            title: 'Basic info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Spot name',
                hint: 'Andrejsala Harbor',
                icon: Icons.place,
              ),
              _LocationPickerField(
                title: 'Pin on the map',
                icon: Icons.map,
                hasLocation: selectedLocation != null,
                subtitle: isDetectingCityCountry
                    ? 'Detecting city/country...'
                    : selectedLocation == null
                    ? 'Choose the spot on map'
                    : detectedCityCountry,
                onTap: chooseLocation,
              ),
              const SizedBox(height: 10),
              _LocationPickerField(
                title: 'Find exact address',
                icon: Icons.search,
                hasLocation: selectedLocation != null,
                subtitle: selectedLocation == null
                    ? 'Type an address and place the pin automatically'
                    : 'Current pin: $detectedCityCountry',
                onTap: findExactAddress,
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'What makes this spot good for car photos?',
                icon: Icons.notes,
                maxLines: 4,
              ),
            ],
          ),
          if (currentUserCanUseVerifiedOnlySpots) ...[
            const SizedBox(height: 16),
            _AddSpotSection(
              title: 'Visibility',
              children: [
                _SettingsSwitchTile(
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
          _AddSpotSection(
            title: 'Temporary schedule',
            children: [
              _TemporarySpotScheduleCard(
                enabled: isTemporarySpot,
                startsAt: temporaryStartsAt,
                expiresAt: temporaryExpiresAt,
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
                  });
                },
                onPickStart: chooseTemporaryStart,
                onPickEnd: chooseTemporaryEnd,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Categories',
            children: [
              _SpotCategoryDropdown(
                value: selectedCategory,
                categories: categoryOptions,
                onChanged: (category) {
                  if (category == null) {
                    return;
                  }

                  setState(() => selectedCategory = category);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (spotCategorySupportsContacts(selectedCategory)) ...[
            _AddSpotSection(
              title: 'Contacts',
              children: [
                _CcsTextField(
                  controller: phoneController,
                  label: 'Phone',
                  hint: '+371 20 000 000',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                _CcsTextField(
                  controller: instagramController,
                  label: 'Instagram',
                  hint: '@ccs.lv or https://instagram.com/ccs.lv',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.url,
                ),
                _CcsTextField(
                  controller: emailController,
                  label: 'Email',
                  hint: 'hello@ccs.lv',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (currentUser.role == UserRole.admin)
                  SpotOwnerSelector(
                    selectedOwner: selectedOwner,
                    onChanged: (owner) =>
                        setState(() => selectedOwner = owner),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _AddSpotSection(
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
          _AddSpotSection(
            title: 'Media',
            children: [
              _SpotPhotoPickerField(
                photoPaths: selectedPhotoPaths,
                onAddPhoto: choosePhoto,
                onRemovePhoto: removePhotoAt,
              ),
              _CcsTextField(
                controller: reelController,
                label: 'Instagram / TikTok video link',
                hint: 'https://instagram.com/reel/...',
                icon: Icons.play_circle,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: addedByController,
                label: 'Added by',
                hint: 'Your profile nickname',
                icon: Icons.person,
                readOnly: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : submitSpot,
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isSubmitting ? Icons.hourglass_top : Icons.send),
                  const SizedBox(width: 10),
                  Text(
                    isSubmitting
                        ? (currentUser.role == UserRole.admin
                              ? 'Creating spot...'
                              : 'Submitting for review...')
                        : (currentUser.role == UserRole.admin
                              ? 'Create Spot'
                              : 'Submit for Review'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MySubmissionsSection(),
        ],
      ),
    );
  }
}


class _PendingBadge extends StatelessWidget {
  final SpotStatus status;

  const _PendingBadge({this.status = SpotStatus.pending});

  String get label {
    switch (status) {
      case SpotStatus.pending:
        return 'pending';
      case SpotStatus.approved:
        return 'live';
      case SpotStatus.rejected:
        return 'rejected';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
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

class _MySubmissionsSection extends StatelessWidget {
  const _MySubmissionsSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: submittedSpots,
      builder: (context, spots, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My submissions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your created spots are saved here. Pending spots wait for review; live spots are already public.',
                style: TextStyle(color: Colors.white54, height: 1.3),
              ),
              const SizedBox(height: 14),
              if (spots.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No submitted spots yet.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ...spots.map(
                  (spot) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubmittedSpotTile(spot: spot),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SubmittedSpotTile extends StatelessWidget {
  final CarSpot spot;

  const _SubmittedSpotTile({required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _PendingBadge(status: spot.status),
                      for (final category in spot.categories.take(2))
                        _SmallTag(
                          label: category,
                          icon: Icons.local_offer,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _TemporarySpotScheduleCard extends StatelessWidget {
  final bool enabled;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  const _TemporarySpotScheduleCard({
    required this.enabled,
    required this.startsAt,
    required this.expiresAt,
    required this.onEnabledChanged,
    required this.onPickStart,
    required this.onPickEnd,
  });

  Widget timeButton({
    required String label,
    required DateTime? value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? blue : Colors.white30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value == null ? 'Choose time' : formatShortDateTime(value),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? blue.withValues(alpha: 0.7) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onEnabledChanged,
            activeThumbColor: blue,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timer, color: blue),
            title: const Text(
              'Temporary spot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: const Text(
              'Use this for meets and events. It disappears after the end time.',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            timeButton(
              label: 'Starts at',
              value: startsAt,
              icon: Icons.play_arrow,
              onTap: onPickStart,
            ),
            const SizedBox(height: 10),
            timeButton(
              label: 'Ends at',
              value: expiresAt,
              icon: Icons.stop,
              onTap: onPickEnd,
            ),
          ],
        ],
      ),
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const defaultCenter = LatLng(56.9496, 24.1052);
  static const defaultZoom = 13.0;

  final mapController = MapController();
  LatLng? pickedLocation;

  @override
  void initState() {
    super.initState();
    pickedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  List<Marker> get markers {
    final location = pickedLocation;

    if (location == null) {
      return [];
    }

    return [
      Marker(
        point: location,
        width: 64,
        height: 64,
        child: const Icon(
          Icons.location_on,
          color: blue,
          size: 56,
          shadows: [
            Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = pickedLocation != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Choose Location'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: pickedLocation ?? defaultCenter,
              initialZoom: defaultZoom,
              minZoom: 4,
              maxZoom: 18,
              backgroundColor: night,
              onTap: (_, point) => setState(() => pickedLocation = point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ccs_app',
                maxNativeZoom: 19,
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap the map where this car spot should be placed.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panel.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.36),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasLocation ? Icons.check_circle : Icons.place,
                        color: hasLocation ? blue : Colors.white54,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasLocation
                              ? 'Location selected'
                              : 'No location selected yet',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: hasLocation
                          ? () => Navigator.pop(context, pickedLocation)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        disabledBackgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Use this Location',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationPickerField extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool hasLocation;
  final String? subtitle;
  final VoidCallback onTap;

  const _LocationPickerField({
    this.title = 'Location',
    this.icon = Icons.map,
    required this.hasLocation,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasLocation ? blue.withValues(alpha: 0.7) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(hasLocation ? Icons.check_circle : icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle ??
                        (hasLocation
                            ? 'Spot location selected on map'
                            : 'Choose the spot on map'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _SpotPhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _SpotPhotoPickerField({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxSpotGalleryPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photoPaths.isNotEmpty
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
                    borderRadius: BorderRadius.circular(14),
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
                      Text(
                        photoPaths.isEmpty
                            ? 'Upload photos'
                            : '${photoPaths.length}/$maxSpotGalleryPhotos photos selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canAddMore
                            ? 'Add up to 4 spot photos. The first photo becomes the Explore thumbnail.'
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
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(photoPaths[index]),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) {
                          return Container(
                            width: 88,
                            height: 88,
                            color: Colors.white.withValues(alpha: 0.06),
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.white38,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? blue.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          index == 0 ? 'Cover' : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => onRemovePhoto(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddSpotSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AddSpotSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          ...children.expand(
            (child) => [
              child,
              if (child != children.last) const SizedBox(height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class _CcsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType keyboardType;
  final bool readOnly;

  const _CcsTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: blue),
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }
}

class SpotOwnerSelector extends StatefulWidget {
  final SpotOwnerAssignment? selectedOwner;
  final ValueChanged<SpotOwnerAssignment?> onChanged;

  const SpotOwnerSelector({
    super.key,
    required this.selectedOwner,
    required this.onChanged,
  });

  @override
  State<SpotOwnerSelector> createState() => _SpotOwnerSelectorState();
}

class _SpotOwnerSelectorState extends State<SpotOwnerSelector> {
  final searchController = TextEditingController();
  String searchText = '';
  late bool isPicking;

  @override
  void initState() {
    super.initState();
    isPicking = widget.selectedOwner == null;
  }

  @override
  void didUpdateWidget(covariant SpotOwnerSelector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedOwner == null && oldWidget.selectedOwner != null) {
      isPicking = true;
    } else if (widget.selectedOwner != null &&
        oldWidget.selectedOwner?.uid != widget.selectedOwner?.uid) {
      isPicking = false;
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String userInitial(String username) {
    final cleanUsername = username.trim();
    return cleanUsername.isEmpty ? '?' : cleanUsername[0].toUpperCase();
  }

  bool userMatchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query) ||
        user.uid.toLowerCase().contains(query);
  }

  void selectOwner(FriendUserData user) {
    widget.onChanged(
      SpotOwnerAssignment(uid: user.uid, username: user.username),
    );
    searchController.clear();
    setState(() {
      searchText = '';
      isPicking = false;
    });
    FocusScope.of(context).unfocus();
  }

  Widget avatarForUser(FriendUserData user) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    userInitial(user.username),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  userInitial(user.username),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }

  Widget ownerSearchField() {
    return TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onTap: () => setState(() => isPicking = true),
      onChanged: (value) => setState(() {
        searchText = value;
        isPicking = true;
      }),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: 'Spot owner',
        hintText: widget.selectedOwner == null
            ? 'Search nickname, name, or email'
            : 'Search to change owner',
        prefixIcon: const Icon(Icons.manage_accounts, color: blue),
        suffixIcon: searchText.trim().isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () {
                  searchController.clear();
                  setState(() => searchText = '');
                },
              )
            : null,
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }

  Widget selectedOwnerCard() {
    final owner = widget.selectedOwner;

    if (owner == null) {
      return const SizedBox.shrink();
    }

    final ownerLabel = owner.username.trim().isEmpty
        ? owner.uid
        : '@${owner.username}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selected owner',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ownerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove owner',
            onPressed: () {
              widget.onChanged(null);
              setState(() => isPicking = true);
            },
            icon: const Icon(Icons.person_remove, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget ownerUserTile(FriendUserData user) {
    final isSelected = widget.selectedOwner?.uid == user.uid;

    return InkWell(
      onTap: () => selectOwner(user),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? blue.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? blue.withValues(alpha: 0.65)
                : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            avatarForUser(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.verified) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified, color: blue, size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email.trim().isEmpty ? user.name : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected ? Icons.check_circle : Icons.add_circle_outline,
              color: isSelected ? blue : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget ownerResults() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersCollection().orderBy('usernameKey').snapshots(),
      builder: (context, snapshot) {
        final users =
            snapshot.data?.docs
                .map((doc) => FriendUserData.fromFirestore(doc))
                .where((user) => user.canAppearInUserLists)
                .where(userMatchesSearch)
                .toList() ??
            const <FriendUserData>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading users...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        if (users.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_search, color: Colors.white38),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No users found.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 290),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => ownerUserTile(users[index]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResults = isPicking || searchText.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ownerSearchField(),
        if (widget.selectedOwner != null) ...[
          const SizedBox(height: 10),
          selectedOwnerCard(),
        ],
        if (showResults) ...[
          const SizedBox(height: 10),
          ownerResults(),
        ],
      ],
    );
  }
}

class OpeningHoursEditor extends StatelessWidget {
  final Map<int, OpeningHoursData> openingHours;
  final ValueChanged<Map<int, OpeningHoursData>> onChanged;

  const OpeningHoursEditor({
    super.key,
    required this.openingHours,
    required this.onChanged,
  });

  OpeningHoursData dayData(int weekday) {
    return openingHours[weekday] ??
        const OpeningHoursData(
          isOpen: false,
          opensAt: '08:00',
          closesAt: '20:00',
        );
  }

  void updateDay(int weekday, OpeningHoursData value) {
    onChanged({...openingHours, weekday: value});
  }

  Future<void> pickTime({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
  }) async {
    final day = dayData(weekday);
    final currentValue = opensAt ? day.opensAt : day.closesAt;
    final currentMinutes = minutesFromClockText(currentValue) ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (picked == null) {
      return;
    }

    final nextTime = clockTextFromTimeOfDay(picked);
    updateDay(
      weekday,
      opensAt ? day.copyWith(opensAt: nextTime) : day.copyWith(closesAt: nextTime),
    );
  }

  Widget timeButton({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
    required String value,
  }) {
    return OutlinedButton.icon(
      onPressed: () => pickTime(
        context: context,
        weekday: weekday,
        opensAt: opensAt,
      ),
      icon: Icon(opensAt ? Icons.login : Icons.logout, size: 16),
      label: Text(value),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
          Padding(
            padding: EdgeInsets.only(
              bottom: weekday == DateTime.sunday ? 0 : 10,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          weekdayLabels[weekday] ?? 'Day',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Switch(
                        value: dayData(weekday).isOpen,
                        activeThumbColor: blue,
                        onChanged: (value) => updateDay(
                          weekday,
                          dayData(weekday).copyWith(isOpen: value),
                        ),
                      ),
                    ],
                  ),
                  if (dayData(weekday).isOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: true,
                            value: dayData(weekday).opensAt,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: false,
                            value: dayData(weekday).closesAt,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Closed',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

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
          content: Text(
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

      await spotsCollection().doc(widget.spot.id).update({
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'businessEditedBy': currentUser.username,
        'businessEditedByUid': currentUser.uid,
        'businessEditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      reviewSpots.value = reviewSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();
      submittedSpots.value = submittedSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();
      savedSpots.value = savedSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
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
          content: Text(
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Service Info'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Contacts',
            children: [
              _CcsTextField(
                controller: phoneController,
                label: 'Phone',
                hint: '+371 20 000 000',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              _CcsTextField(
                controller: instagramController,
                label: 'Instagram',
                hint: '@ccs.lv or https://instagram.com/ccs.lv',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: emailController,
                label: 'Email',
                hint: 'hello@ccs.lv',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
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
              label: Text(isSaving ? 'Saving...' : 'Save Service Info'),
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

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCS'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: savedSpots,
        builder: (context, spots, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Saved Spots',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spots.isEmpty
                    ? 'Save approved spots from Explore, Map, or Spot pages.'
                    : '${spots.length} saved car spots.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (spots.isEmpty)
                const EmptyStateCard(
                  icon: Icons.bookmark_border,
                  title: 'No saved spots yet',
                  text: 'Tap the bookmark on a spot to keep it here.',
                )
              else
                for (final spot in spots) ...[
                  SavedSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

const pinnedChatIdsPreferenceKey = 'pinned_chat_ids_v1';

Future<List<String>> loadPinnedChatIds() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(pinnedChatIdsPreferenceKey) ?? <String>[];
}

Future<void> savePinnedChatIds(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(pinnedChatIdsPreferenceKey, ids.take(6).toList());
}


Widget chatAvatarWidget(ChatThreadData chat, String currentUid) {
  final photoUrl = chat.directPhotoUrlForCurrentUser(currentUid);

  if (!chat.isGroup && isNetworkUrl(photoUrl)) {
    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.person_outline, color: blue),
      ),
    );
  }

  if (chat.isGroup && isNetworkUrl(chat.avatarUrl)) {
    return ClipOval(
      child: Image.network(
        chat.avatarUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.groups, color: blue),
      ),
    );
  }

  return Icon(
    chat.isGroup ? Icons.groups : Icons.person_outline,
    color: blue,
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<String> pinnedChatIds = const [];
  bool showGroupsTab = false;

  @override
  void initState() {
    super.initState();
    loadPins();
  }

  Future<void> loadPins() async {
    final ids = await loadPinnedChatIds();
    if (mounted) {
      setState(() => pinnedChatIds = ids);
    }
  }

  Future<void> openNewChat(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
    loadPins();
  }

  Future<void> openChatManager(
    BuildContext context,
    List<ChatThreadData> chats,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatManageScreen(
          chats: chats,
          currentPinnedIds: pinnedChatIds,
        ),
      ),
    );
    loadPins();
  }

  List<ChatThreadData> sortedChats(List<ChatThreadData> chats) {
    final pinnedSet = pinnedChatIds.toSet();
    chats.sort((a, b) {
      final aPinned = pinnedSet.contains(a.id);
      final bPinned = pinnedSet.contains(b.id);

      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }

      if (aPinned && bPinned) {
        return pinnedChatIds.indexOf(a.id).compareTo(pinnedChatIds.indexOf(b.id));
      }

      return b.updatedAtMillis.compareTo(a.updatedAtMillis);
    });
    return chats;
  }

  Widget sectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget chatSection({
    required String title,
    required String emptyText,
    required List<ChatThreadData> chats,
    required String currentUid,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(title, chats.length),
          if (chats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
            )
          else
            for (final chat in chats) ...[
              ChatThreadTile(
                chat: chat,
                currentUid: currentUid,
                pinned: pinnedChatIds.contains(chat.id),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCS'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      floatingActionButton: firebaseUser == null
          ? null
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: chatsCollection()
                  .where('memberIds', arrayContains: firebaseUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final chats = snapshot.data?.docs
                        .map((doc) => ChatThreadData.fromFirestore(doc))
                        .toList() ??
                    <ChatThreadData>[];

                return FloatingActionButton(
                  onPressed: () => openChatManager(context, chats),
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.tune),
                );
              },
            ),
      body: firebaseUser == null
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: EmptyStateCard(
                icon: Icons.chat_bubble_outline,
                title: 'Log in required',
                text: 'Log in before using chat.',
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: chatsCollection()
                  .where('memberIds', arrayContains: firebaseUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final chats = snapshot.data?.docs
                        .map((doc) => ChatThreadData.fromFirestore(doc))
                        .toList() ??
                    <ChatThreadData>[];
                final directChats = sortedChats(
                  chats.where((chat) => !chat.isGroup).toList(),
                );
                final groupChats = sortedChats(
                  chats.where((chat) => chat.isGroup).toList(),
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Messages with friends and groups',
                                style: TextStyle(
                                  color: Colors.white54,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => openNewChat(context),
                          style: IconButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.person_outline),
                            label: Text('Chats'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.groups),
                            label: Text('Groups'),
                          ),
                        ],
                        selected: {showGroupsTab},
                        onSelectionChanged: (value) {
                          setState(() => showGroupsTab = value.first);
                        },
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white
                                : Colors.white70,
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? blue
                                : panel,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: blue),
                        ),
                      )
                    else if (chats.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'No chats yet',
                        text: 'Start a chat with a friend or create a group.',
                      )
                    else if (!showGroupsTab)
                      chatSection(
                        title: 'Chats',
                        emptyText: 'No direct chats yet.',
                        chats: directChats,
                        currentUid: firebaseUser.uid,
                      )
                    else
                      chatSection(
                        title: 'Groups',
                        emptyText: 'No groups yet.',
                        chats: groupChats,
                        currentUid: firebaseUser.uid,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class ChatThreadTile extends StatelessWidget {
  final ChatThreadData chat;
  final String currentUid;
  final bool pinned;

  const ChatThreadTile({
    super.key,
    required this.chat,
    required this.currentUid,
    this.pinned = false,
  });

  String? otherUserId() {
    if (chat.isGroup) {
      return null;
    }

    for (final uid in chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  Widget directAvatar(String uid) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: usersCollection().doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final user = FriendUserData.fromFirestore(snapshot.data!);
          return UserAvatarCircle(user: user, size: 46);
        }

        return const UserAvatarFallback(size: 46, icon: Icons.person_outline);
      },
    );
  }

  Widget avatar() {
    if (chat.isGroup) {
      final photoUrl = chat.photoUrl.trim();
      if (isNetworkUrl(photoUrl)) {
        return ClipOval(
          child: Image.network(
            photoUrl,
            width: 46,
            height: 46,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const UserAvatarFallback(
              size: 46,
              icon: Icons.groups,
            ),
          ),
        );
      }

      return const UserAvatarFallback(size: 46, icon: Icons.groups);
    }

    final uid = otherUserId();
    return uid == null
        ? const UserAvatarFallback(size: 46, icon: Icons.person_outline)
        : directAvatar(uid);
  }

  @override
  Widget build(BuildContext context) {
    final title = chat.titleForCurrentUser(currentUid);
    final subtitle = chat.subtitleForCurrentUser(currentUid);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatConversationScreen(chat: chat),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: pinned ? blue.withValues(alpha: 0.75) : Colors.white12,
            width: pinned ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        const Icon(Icons.push_pin, color: blue, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class UserAvatarFallback extends StatelessWidget {
  final double size;
  final IconData icon;

  const UserAvatarFallback({
    super.key,
    required this.size,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Icon(icon, color: blue, size: size * 0.5),
    );
  }
}

class UserAvatarCircle extends StatelessWidget {
  final FriendUserData user;
  final double size;

  const UserAvatarCircle({
    super.key,
    required this.user,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(user.photoUrl)
                ? Image.network(
                    user.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(
                        user.username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      user.username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
      ),
    );
  }
}

class ChatManageScreen extends StatefulWidget {
  final List<ChatThreadData> chats;
  final List<String> currentPinnedIds;

  const ChatManageScreen({
    super.key,
    required this.chats,
    required this.currentPinnedIds,
  });

  @override
  State<ChatManageScreen> createState() => _ChatManageScreenState();
}

class _ChatManageScreenState extends State<ChatManageScreen> {
  late List<String> pinnedIds;

  @override
  void initState() {
    super.initState();
    pinnedIds = [...widget.currentPinnedIds];
  }

  Future<void> togglePin(ChatThreadData chat) async {
    final sameTypePinned = pinnedIds
        .where((id) => widget.chats.any((item) => item.id == id && item.isGroup == chat.isGroup))
        .toList();

    setState(() {
      if (pinnedIds.contains(chat.id)) {
        pinnedIds.remove(chat.id);
      } else {
        if (sameTypePinned.length >= 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                chat.isGroup
                    ? 'You can pin up to 3 groups.'
                    : 'You can pin up to 3 direct chats.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }
        pinnedIds.add(chat.id);
      }
    });

    await savePinnedChatIds(pinnedIds);
  }

  Future<void> movePinned(String chatId, int direction) async {
    final index = pinnedIds.indexOf(chatId);
    if (index < 0) {
      return;
    }

    final newIndex = (index + direction).clamp(0, pinnedIds.length - 1).toInt();
    if (newIndex == index) {
      return;
    }

    setState(() {
      final id = pinnedIds.removeAt(index);
      pinnedIds.insert(newIndex, id);
    });

    await savePinnedChatIds(pinnedIds);
  }

  Widget section(String title, List<ChatThreadData> chats) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (chats.isEmpty)
            const Text(
              'Nothing here yet.',
              style: TextStyle(color: Colors.white54),
            )
          else
            for (final chat in chats) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chat.titleForCurrentUser(
                        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: pinnedIds.contains(chat.id)
                        ? () => movePinned(chat.id, -1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: pinnedIds.contains(chat.id)
                        ? () => movePinned(chat.id, 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  IconButton(
                    tooltip: pinnedIds.contains(chat.id) ? 'Unpin' : 'Pin',
                    onPressed: () => togglePin(chat),
                    icon: Icon(
                      pinnedIds.contains(chat.id)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color: pinnedIds.contains(chat.id) ? blue : Colors.white54,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directChats = widget.chats.where((chat) => !chat.isGroup).toList();
    final groupChats = widget.chats.where((chat) => chat.isGroup).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Chat View'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Text(
            'Pin up to 3 direct chats and 3 groups. Use arrows to change pinned order.',
            style: TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 18),
          section('Direct chats', directChats),
          const SizedBox(height: 16),
          section('Groups', groupChats),
        ],
      ),
    );
  }
}

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final searchController = TextEditingController();
  final groupNameController = TextEditingController();
  final Set<String> selectedUserIds = {};
  bool groupMode = false;
  String searchText = '';
  bool isCreating = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      setState(() => searchText = searchController.text);
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    groupNameController.dispose();
    super.dispose();
  }

  bool matchesSearch(FriendUserData user) {
    final query = searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return user.username.toLowerCase().contains(query) ||
        user.name.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query);
  }

  Future<void> openDirectChat(FriendUserData user) async {
    setState(() => isCreating = true);

    try {
      final chatId = await createOrOpenDirectChat(user);
      final chat = ChatThreadData(
        id: chatId,
        isGroup: false,
        name: '',
        memberIds: [currentUser.uid, user.uid],
        memberUsernames: [currentUser.username, user.username],
        lastMessage: '',
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not open chat: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Future<void> createGroup(List<FriendUserData> friends) async {
    final selected = friends
        .where((user) => selectedUserIds.contains(user.uid))
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Pick at least one friend for a group.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isCreating = true);

    try {
      final chatId = await createGroupChat(
        name: groupNameController.text,
        users: selected,
      );
      final groupName = groupNameController.text.trim().isEmpty
          ? selected.map((user) => user.username).take(3).join(', ')
          : groupNameController.text.trim();
      final chat = ChatThreadData(
        id: chatId,
        isGroup: true,
        name: groupName,
        memberIds: [currentUser.uid, ...selected.map((user) => user.uid)],
        memberUsernames: [
          currentUser.username,
          ...selected.map((user) => user.username),
        ],
        lastMessage: '',
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not create group: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isCreating = false);
      }
    }
  }

  Widget userAvatar(FriendUserData user) {
    return UserAvatarCircle(user: user, size: 44);
  }

  Widget friendTile(FriendUserData user) {
    final selected = selectedUserIds.contains(user.uid);

    return InkWell(
      onTap: isCreating
          ? null
          : groupMode
          ? () {
              setState(() {
                if (selected) {
                  selectedUserIds.remove(user.uid);
                } else {
                  selectedUserIds.add(user.uid);
                }
              });
            }
          : () => openDirectChat(user),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? blue : Colors.white12,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            userAvatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            if (groupMode)
              Checkbox(
                value: selected,
                onChanged: (_) {
                  setState(() {
                    if (selected) {
                      selectedUserIds.remove(user.uid);
                    } else {
                      selectedUserIds.add(user.uid);
                    }
                  });
                },
                activeColor: blue,
                checkColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('New Chat'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: FutureBuilder<List<FriendUserData>>(
        future: loadCurrentFriendUsers(),
        builder: (context, snapshot) {
          final friends =
              snapshot.data?.where(matchesSearch).toList() ??
              const <FriendUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.person_outline),
                          label: Text('Direct'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.groups),
                          label: Text('Group'),
                        ),
                      ],
                      selected: {groupMode},
                      onSelectionChanged: (value) {
                        setState(() {
                          groupMode = value.first;
                          selectedUserIds.clear();
                        });
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : Colors.white70,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? blue
                              : panel,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CcsTextField(
                controller: searchController,
                label: 'Find friend',
                hint: '@username',
                icon: Icons.search,
              ),
              if (groupMode) ...[
                const SizedBox(height: 12),
                _CcsTextField(
                  controller: groupNameController,
                  label: 'Group name',
                  hint: 'Night drive crew',
                  icon: Icons.groups,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isCreating ? null : () => createGroup(friends),
                    icon: Icon(isCreating ? Icons.hourglass_top : Icons.check),
                    label: Text(
                      selectedUserIds.isEmpty
                          ? 'Create Group'
                          : 'Create Group (${selectedUserIds.length + 1})',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (friends.isEmpty)
                const EmptyStateCard(
                  icon: Icons.group_outlined,
                  title: 'No friends found',
                  text: 'Add friends first, then start a chat here.',
                )
              else
                for (final friend in friends) friendTile(friend),
            ],
          );
        },
      ),
    );
  }
}


class GroupSettingsScreen extends StatefulWidget {
  final ChatThreadData chat;

  const GroupSettingsScreen({super.key, required this.chat});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  bool isSaving = false;
  String photoUrl = '';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.chat.name);
    descriptionController = TextEditingController(text: widget.chat.description);
    photoUrl = widget.chat.photoUrl;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickGroupAvatar() async {
    final path = await pickPhotoFromPhone(
      context,
      cropAspectRatio: 1,
      cropShape: PhotoCropShape.circle,
    );

    if (path == null || path.trim().isEmpty) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final uploadedUrl = await uploadImageToR2(
        r2Path: 'users/${currentUser.uid}/group_${safeR2Path(widget.chat.id)}_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        localPhotoPath: path,
        maxLongSide: r2AvatarPhotoMaxLongSide,
      );

      await chatsCollection().doc(widget.chat.id).set({
        'photoUrl': uploadedUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => photoUrl = uploadedUrl);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update group photo: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> saveGroup() async {
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();

    setState(() => isSaving = true);

    try {
      await chatsCollection().doc(widget.chat.id).set({
        'name': name.isEmpty ? widget.chat.name : name,
        'description': description,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'Could not update group: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget avatarPreview() {
    if (isNetworkUrl(photoUrl)) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const UserAvatarFallback(
            size: 96,
            icon: Icons.groups,
          ),
        ),
      );
    }

    return const UserAvatarFallback(size: 96, icon: Icons.groups);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Group Settings'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: isSaving ? null : saveGroup,
            icon: Icon(isSaving ? Icons.hourglass_top : Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Center(
            child: InkWell(
              onTap: isSaving ? null : pickGroupAvatar,
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  avatarPreview(),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _CcsTextField(
            controller: nameController,
            label: 'Group name',
            hint: 'Night drive crew',
            icon: Icons.groups,
          ),
          const SizedBox(height: 12),
          _CcsTextField(
            controller: descriptionController,
            label: 'Group description',
            hint: 'What is this group about?',
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : saveGroup,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.check),
              label: const Text('Save Group'),
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

class ChatConversationScreen extends StatefulWidget {
  final ChatThreadData chat;

  const ChatConversationScreen({super.key, required this.chat});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final messageController = TextEditingController();
  bool isSending = false;

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty || isSending) {
      return;
    }

    setState(() => isSending = true);

    try {
      await sendChatMessage(chatId: widget.chat.id, text: text);
      messageController.clear();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not send message: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }


  String? otherUserId(String currentUid) {
    if (widget.chat.isGroup) {
      return null;
    }

    for (final uid in widget.chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  String otherUsername(String currentUid) {
    for (var index = 0; index < widget.chat.memberIds.length; index++) {
      final uid = widget.chat.memberIds[index];
      if (uid == currentUid) {
        continue;
      }

      if (index < widget.chat.memberUsernames.length) {
        return widget.chat.memberUsernames[index];
      }
    }

    return '';
  }

  void openChatUserProfile(String currentUid) {
    final uid = otherUserId(currentUid);

    if (uid == null) {
      return;
    }

    openUserProfile(
      context,
      uid: uid,
      fallbackUsername: otherUsername(currentUid),
    );
  }

  Widget messageBubble(ChatMessageData message, String currentUid) {
    final mine = message.senderUid == currentUid;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? blue : panel,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 5),
            bottomRight: Radius.circular(mine ? 5 : 16),
          ),
          border: mine ? null : Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!mine && widget.chat.isGroup) ...[
              Text(
                '@${message.senderUsername}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final currentUid = firebaseUser?.uid ?? currentUser.uid;
    final title = widget.chat.titleForCurrentUser(currentUid);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: widget.chat.isGroup
            ? InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupSettingsScreen(chat: widget.chat),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(title)),
                    ],
                  ),
                ),
              )
            : InkWell(
                onTap: () => openChatUserProfile(currentUid),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(title)),
                    ],
                  ),
                ),
              ),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: widget.chat.isGroup
            ? [
                IconButton(
                  tooltip: 'Group settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupSettingsScreen(chat: widget.chat),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Open profile',
                  onPressed: () => openChatUserProfile(currentUid),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: chatMessagesCollection(widget.chat.id)
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snapshot) {
                final messages =
                    snapshot.data?.docs
                        .map((doc) => ChatMessageData.fromFirestore(doc))
                        .where((message) => message.text.trim().isNotEmpty)
                        .toList() ??
                    const <ChatMessageData>[];

                if (messages.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: EmptyStateCard(
                      icon: Icons.chat_bubble_outline,
                      title: 'No messages yet',
                      text: 'Send the first message.',
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    for (final message in messages)
                      messageBubble(message, currentUid),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: panel,
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: blue),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isSending ? null : sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(isSending ? Icons.hourglass_top : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserProfileData {
  final String username;
  final String cityCountry;
  final String bio;
  final String instagram;
  final String tiktok;
  final String telegram;
  final String? avatarPath;
  final String? photoUrl;

  const UserProfileData({
    required this.username,
    required this.cityCountry,
    required this.bio,
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    this.avatarPath,
    this.photoUrl,
  });

  factory UserProfileData.fromCurrentUser() {
    final settings = userSettings.value;

    return UserProfileData(
      username: currentUser.username,
      cityCountry: '${currentUser.city}, ${currentUser.country}',
      bio: currentUser.bio,
      instagram: settings.instagram,
      tiktok: settings.tiktok,
      telegram: settings.telegram,
      avatarPath: currentUser.avatarPath,
      photoUrl: currentUser.photoUrl,
    );
  }
}

class GarageCar {
  final String name;
  final String description;
  final String buildType;
  final String useType;
  final List<String> tags;
  final String? photoPath;
  final List<String> photoPaths;

  const GarageCar({
    required this.name,
    required this.description,
    this.buildType = '',
    this.useType = '',
    this.tags = const [],
    this.photoPath,
    this.photoPaths = const [],
  });

  List<String> get galleryPhotos {
    final sources = <String>[];

    for (final source in photoPaths) {
      final cleanSource = source.trim();
      if (cleanSource.isNotEmpty && !sources.contains(cleanSource)) {
        sources.add(cleanSource);
      }
    }

    final cover = photoPath?.trim() ?? '';
    if (cover.isNotEmpty && !sources.contains(cover)) {
      sources.insert(0, cover);
    }

    return sources.take(maxGaragePhotos).toList();
  }

  String? get coverPhotoPath {
    final photos = galleryPhotos;
    return photos.isEmpty ? null : photos.first;
  }

  GarageCar copyWith({
    String? name,
    String? description,
    String? buildType,
    String? useType,
    List<String>? tags,
    String? photoPath,
    List<String>? photoPaths,
  }) {
    final nextPhotoPaths = photoPaths ?? this.photoPaths;
    final nextPhotoPath = photoPath ??
        (nextPhotoPaths.isNotEmpty ? nextPhotoPaths.first : this.photoPath);

    return GarageCar(
      name: name ?? this.name,
      description: description ?? this.description,
      buildType: buildType ?? this.buildType,
      useType: useType ?? this.useType,
      tags: tags ?? this.tags,
      photoPath: nextPhotoPath,
      photoPaths: nextPhotoPaths.take(maxGaragePhotos).toList(),
    );
  }

  factory GarageCar.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);
    final photoPath = data['photoPath'];
    final legacyPhotoPath = photoPath is String && photoPath.trim().isNotEmpty
        ? photoPath.trim()
        : null;
    final photos = stringListFromFirebase(data['photoPaths'], const []);
    final gallery = photos.isNotEmpty
        ? photos.take(maxGaragePhotos).toList()
        : legacyPhotoPath == null
        ? const <String>[]
        : [legacyPhotoPath];

    return GarageCar(
      name: stringFromFirebase(data['name'], 'BMW E46 Coupe'),
      description: stringFromFirebase(
        data['description'],
        'Night drive setup for city shoots and clean street parking spots.',
      ),
      buildType: stringFromFirebase(data['buildType'], ''),
      useType: stringFromFirebase(data['useType'], ''),
      tags: stringListFromFirebase(data['tags'], const []),
      photoPath: gallery.isEmpty ? legacyPhotoPath : gallery.first,
      photoPaths: gallery,
    );
  }

  Map<String, Object?> toFirebase() {
    final gallery = galleryPhotos;

    return {
      'name': name,
      'description': description,
      'buildType': buildType,
      'useType': useType,
      'tags': tags,
      'photoPath': gallery.isEmpty ? photoPath : gallery.first,
      'photoPaths': gallery,
    };
  }
}


List<GarageCar> defaultGarageCars() {
  return const [
    GarageCar(
      name: 'BMW E46 Coupe',
      description:
          'Night drive setup for city shoots and clean street parking spots.',
    ),
  ];
}

List<GarageCar> garageCarsFromFirebase(Object? value) {
  if (value is List) {
    final cars = value.map(GarageCar.fromFirebase).toList();

    if (cars.isNotEmpty) {
      return cars;
    }
  }

  return defaultGarageCars();
}

class PublicUserProfileData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final String bio;
  final String city;
  final String country;
  final UserRole role;
  final bool verified;
  final UserSettingsData settings;
  final List<GarageCar> garage;
  final bool deleted;

  const PublicUserProfileData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.bio,
    required this.city,
    required this.country,
    required this.role,
    required this.verified,
    required this.settings,
    required this.garage,
    required this.deleted,
  });

  bool get canCurrentUserView {
    return currentUser.role == UserRole.admin ||
        currentUser.uid == uid ||
        settings.publicProfile;
  }

  String get cityCountry {
    final cleanCity = city.trim().isEmpty ? 'Riga' : city.trim();
    final cleanCountry = country.trim().isEmpty ? 'Latvia' : country.trim();
    return '$cleanCity, $cleanCountry';
  }

  factory PublicUserProfileData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final role = roleFromFirebase(data['role']);

    return PublicUserProfileData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      bio: stringFromFirebase(data['bio'], 'Find. Drive. Shoot.'),
      city: stringFromFirebase(data['city'], 'Riga'),
      country: stringFromFirebase(data['country'], 'Latvia'),
      role: role,
      verified: role == UserRole.admin || data['verified'] == true,
      settings: UserSettingsData.fromFirebase(data['settings']),
      garage: garageCarsFromFirebase(data['garage']),
      deleted: data['deleted'] == true,
    );
  }
}

void openUserProfile(
  BuildContext context, {
  required String uid,
  String fallbackUsername = '',
}) {
  final cleanUid = uid.trim();

  if (cleanUid.isEmpty) {
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PublicUserProfileScreen(
        userId: cleanUid,
        fallbackUsername: fallbackUsername,
      ),
    ),
  );
}

List<String> splitCityCountry(String value) {
  final parts = value.split(',');
  final city = parts.isNotEmpty && parts.first.trim().isNotEmpty
      ? parts.first.trim()
      : 'Riga';
  final countryText = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
  final country = countryText.isNotEmpty ? countryText : 'Latvia';

  return [city, country];
}

Future<void> saveProfileToFirebase(UserProfileData profile) async {
  final cityCountry = splitCityCountry(profile.cityCountry);
  final previousUsername = currentUser.username;
  final cleanUsername = await reserveUsernameForCurrentUser(
    preferredUsername: profile.username,
    previousUsername: previousUsername,
  );

  var nextPhotoUrl = currentUser.photoUrl;
  String? nextAvatarPath = profile.avatarPath;

  if (localFileExists(profile.avatarPath)) {
    nextPhotoUrl = await uploadUserAvatarPhoto(
      userId: currentUser.uid,
      localPhotoPath: profile.avatarPath!,
    );
    nextAvatarPath = null;
  } else if (isNetworkUrl(profile.avatarPath)) {
    nextPhotoUrl = profile.avatarPath;
    nextAvatarPath = null;
  }

  currentUser = AppUser(
    uid: currentUser.uid,
    name: currentUser.name,
    username: cleanUsername,
    email: currentUser.email,
    photoUrl: nextPhotoUrl,
    bio: profile.bio,
    avatarPath: nextAvatarPath,
    role: currentUser.role,
    verified: currentUser.verified,
    city: cityCountry[0],
    country: cityCountry[1],
  );

  final nextSettings = userSettings.value.copyWith(
    instagram: profile.instagram.trim(),
    tiktok: profile.tiktok.trim(),
    telegram: profile.telegram.trim(),
  );
  userSettings.value = nextSettings;

  await saveCurrentUserFields({
    'username': cleanUsername,
    'usernameKey': usernameKey(cleanUsername),
    'bio': profile.bio,
    'photoUrl': nextPhotoUrl,
    'avatarPath': nextAvatarPath,
    'city': cityCountry[0],
    'country': cityCountry[1],
    'settings': nextSettings.toFirebase(),
  });
}

Future<void> saveGarageToFirebase(List<GarageCar> cars) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uploadedCars = <GarageCar>[];

  for (var carIndex = 0; carIndex < cars.length; carIndex++) {
    final car = cars[carIndex];
    final uploadedPhotoPaths = <String>[];
    final photoSources = car.galleryPhotos.take(maxGaragePhotos).toList();

    for (var photoIndex = 0; photoIndex < photoSources.length; photoIndex++) {
      final source = photoSources[photoIndex];

      if (firebaseUser != null && localFileExists(source)) {
        final uploadedPhotoUrl = await uploadGarageCarPhoto(
          userId: firebaseUser.uid,
          carIndex: carIndex,
          photoIndex: photoIndex,
          localPhotoPath: source,
        );
        uploadedPhotoPaths.add(uploadedPhotoUrl);
      } else if (source.trim().isNotEmpty) {
        uploadedPhotoPaths.add(source.trim());
      }
    }

    uploadedCars.add(
      GarageCar(
        name: car.name,
        description: car.description,
        buildType: car.buildType,
        useType: car.useType,
        tags: car.tags,
        photoPath: uploadedPhotoPaths.isEmpty ? null : uploadedPhotoPaths.first,
        photoPaths: uploadedPhotoPaths,
      ),
    );
  }

  garageCars.value = uploadedCars;

  await saveCurrentUserFields({
    'garage': uploadedCars.map((car) => car.toFirebase()).toList(),
  });
}


Future<void> saveSettingsToFirebase(UserSettingsData settings) async {
  userSettings.value = settings;

  await saveCurrentUserFields({'settings': settings.toFirebase()});
}


Widget profileMessageButton(BuildContext context, FriendUserData user) {
  if (user.uid == currentUser.uid) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => openMessageToUserFromContext(context, user),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Message'),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isSigningOut = false;

  UserProfileData profile = UserProfileData.fromCurrentUser();
  List<GarageCar> cars = garageCars.value;

  Future<void> editProfile() async {
    final updatedProfile = await Navigator.push<UserProfileData>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
    );

    if (!mounted || updatedProfile == null) {
      return;
    }

    try {
      await saveProfileToFirebase(updatedProfile);

      if (!mounted) {
        return;
      }

      setState(() => profile = UserProfileData.fromCurrentUser());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Profile saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save profile: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> editGarage(int index) async {
    final updatedCar = await Navigator.push<GarageCar>(
      context,
      MaterialPageRoute(builder: (_) => EditGarageScreen(car: cars[index])),
    );

    if (!mounted || updatedCar == null) {
      return;
    }

    final nextCars = [...cars];
    nextCars[index] = updatedCar;
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Garage saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save garage: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  Future<void> addCar() async {
    final newCar = await Navigator.push<GarageCar>(
      context,
      MaterialPageRoute(builder: (_) => const EditGarageScreen()),
    );

    if (!mounted || newCar == null) {
      return;
    }

    final nextCars = [...cars, newCar];
    setState(() => cars = nextCars);

    try {
      await saveGarageToFirebase(nextCars);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Car added to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save car: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void openFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void openAdminPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminReviewScreen()),
    );
  }

  Future<void> signOut() async {
    if (isSigningOut) {
      return;
    }

    setState(() => isSigningOut = true);

    try {
      await signOutCurrentAccount();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not sign out: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSigningOut = false);
      }
    }
  }

  String get garageValue {
    if (cars.length == 1) {
      return '1 car';
    }

    return '${cars.length} cars';
  }

  String get baseValue {
    final city = profile.cityCountry.split(',').first.trim();

    if (city.isEmpty) {
      return 'Riga';
    }

    return city;
  }

  List<String> get profileTags {
    final tags = <String>{};

    for (final car in cars) {
      tags.addAll(car.tags);
    }

    return tags.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCS'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: submittedSpots,
        builder: (context, spots, _) {
          final pendingCount = spots
              .where((spot) => spot.status == SpotStatus.pending)
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _ProfileHeader(profile: profile, onEdit: editProfile),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.pending_actions,
                      value: '$pendingCount',
                      label: 'Pending',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.directions_car,
                      value: garageValue,
                      label: 'Garage',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.location_on,
                      value: baseValue,
                      label: 'Base',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _ProfileSocialLinksSection(),
              const SizedBox(height: 16),
              for (var i = 0; i < cars.length; i++) ...[
                _GarageCard(car: cars[i], onEdit: () => editGarage(i)),
                const SizedBox(height: 16),
              ],
              ValueListenableBuilder<List<CarSpot>>(
                valueListenable: savedSpots,
                builder: (context, saved, _) {
                  return _ProfileSavedSpotsPreview(spots: saved);
                },
              ),
              const SizedBox(height: 16),
              _ProfileSubmissionsPreview(spots: spots),
              const SizedBox(height: 16),
              _ProfileActionTile(
                icon: Icons.group_add,
                title: 'Friends',
                subtitle: 'Send requests, accept invites, and manage friends',
                onTap: openFriends,
              ),
              const SizedBox(height: 10),
              if (currentUser.role == UserRole.admin) ...[
                _ProfileActionTile(
                  icon: Icons.admin_panel_settings,
                  title: 'Admin Panel',
                  subtitle: 'Review spots and manage verified users',
                  onTap: openAdminPanel,
                ),
                const SizedBox(height: 10),
              ],
              _ProfileActionTile(
                icon: Icons.directions_car,
                title: 'Add another car',
                subtitle: 'Add another car to your garage',
                onTap: addCar,
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Account, privacy, notifications',
                onTap: openSettings,
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.logout,
                title: isSigningOut ? 'Signing out...' : 'Sign out',
                subtitle: 'Log out of this Google account',
                color: Colors.redAccent,
                onTap: signOut,
              ),
            ],
          );
        },
      ),
    );
  }
}

class PublicUserProfileScreen extends StatelessWidget {
  final String userId;
  final String fallbackUsername;

  const PublicUserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackUsername = '',
  });

  Widget avatar(PublicUserProfileData profile) {
    Widget fallback() {
      final initial = profile.username.trim().isEmpty
          ? 'C'
          : profile.username.trim()[0].toUpperCase();

      return Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: blue,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.5)),
      ),
      child: ClipOval(
        child: localFileExists(profile.avatarPath)
            ? Image.file(File(profile.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(profile.photoUrl)
            ? Image.network(
                profile.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }

  Widget profileHeader(PublicUserProfileData profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          avatar(profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (profile.verified) ...[
                      const SizedBox(width: 7),
                      const Icon(Icons.verified, color: blue, size: 19),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  profile.bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: blue, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        profile.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget messageButton(BuildContext context, PublicUserProfileData profile) {
    if (profile.uid == currentUser.uid) {
      return const SizedBox.shrink();
    }

    final user = FriendUserData(
      uid: profile.uid,
      username: profile.username,
      name: profile.name,
      email: profile.email,
      photoUrl: profile.photoUrl,
      avatarPath: profile.avatarPath,
      verified: profile.verified,
      role: profile.role,
      banned: false,
      deleted: false,
    );

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () async {
          try {
            final chatId = await createOrOpenDirectChat(user);
            final chat = ChatThreadData(
              id: chatId,
              isGroup: false,
              name: '',
              photoUrl: '',
              memberIds: [currentUser.uid, user.uid],
              memberUsernames: [currentUser.username, user.username],
              memberPhotoUrls: [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
              lastMessage: '',
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            );

            if (!context.mounted) {
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatConversationScreen(chat: chat),
              ),
            );
          } catch (error) {
            if (!context.mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: Text(
                  'Could not open chat: $error',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Message'),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget socialLinks(PublicUserProfileData profile) {
    final settings = profile.settings;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Social links',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _SocialLinkRow(
            icon: Icons.camera_alt,
            label: 'Instagram',
            value: settings.instagram,
          ),
          const SizedBox(height: 10),
          _SocialLinkRow(
            icon: Icons.music_note,
            label: 'TikTok',
            value: settings.tiktok,
          ),
          const SizedBox(height: 10),
          _SocialLinkRow(
            icon: Icons.send,
            label: 'Telegram',
            value: settings.telegram,
          ),
        ],
      ),
    );
  }

  Widget profileBody(BuildContext context, PublicUserProfileData profile) {
    final visibleGarage = profile.settings.showGarage
        ? profile.garage
        : const <GarageCar>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        profileHeader(profile),
        const SizedBox(height: 12),
        messageButton(context, profile),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ProfileStatTile(
                icon: Icons.directions_car,
                value: '${visibleGarage.length}',
                label: 'Cars',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileStatTile(
                icon: Icons.location_on,
                value: profile.city.trim().isEmpty ? 'Riga' : profile.city,
                label: 'Base',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileStatTile(
                icon: profile.verified ? Icons.verified : Icons.person,
                value: profile.verified ? 'Yes' : 'No',
                label: 'Verified',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        socialLinks(profile),
        const SizedBox(height: 16),
        if (visibleGarage.isEmpty)
          const EmptyStateCard(
            icon: Icons.directions_car,
            title: 'No garage shared',
            text: 'This driver has not shared car builds yet.',
          )
        else
          for (final car in visibleGarage) ...[
            _GarageCard(car: car),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = fallbackUsername.trim().isEmpty
        ? 'Profile'
        : '@${fallbackUsername.replaceAll('@', '')}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersCollection().doc(userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data;

          if (doc == null || !doc.exists) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile not found',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          final profile = PublicUserProfileData.fromFirestore(doc);

          if (profile.deleted) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile deleted',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          if (!profile.canCurrentUserView) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.lock,
                title: 'Private profile',
                text: 'This driver keeps their profile private.',
              ),
            );
          }

          return profileBody(context, profile);
        },
      ),
    );
  }
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final searchController = TextEditingController();
  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<FriendUserData?> loadFriendUser(String uid) async {
    final snapshot = await usersCollection().doc(uid).get();

    if (!snapshot.exists) {
      return null;
    }

    return FriendUserData.fromFirestore(snapshot);
  }

  void showFriendActionMessage(String message, {Color color = blue}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> sendRequest(FriendUserData user) async {
    try {
      await sendFriendRequestToUser(user);
      showFriendActionMessage('Friend request sent to ${user.username}.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not send request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> acceptRequest(FriendRequestData request) async {
    try {
      await acceptFriendRequest(request);
      showFriendActionMessage('${request.fromUsername} added to friends.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not accept request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> declineRequest(FriendRequestData request) async {
    try {
      await declineFriendRequest(request);
      showFriendActionMessage('Friend request declined.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not decline request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> cancelRequest(FriendRequestData request) async {
    try {
      await cancelFriendRequest(request);
      showFriendActionMessage('Friend request cancelled.');
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not cancel request: $error',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> removeFriend(FriendUserData user) async {
    try {
      await removeFriendship(user.uid);
      showFriendActionMessage(
        '${user.username} removed from friends.',
        color: Colors.redAccent,
      );
      setState(() {});
    } catch (error) {
      showFriendActionMessage(
        'Could not remove friend: $error',
        color: Colors.redAccent,
      );
    }
  }

  Widget userAvatar({
    required String username,
    String? photoUrl,
    String? avatarPath,
    bool verified = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: blue.withValues(alpha: 0.45)),
          ),
          child: ClipOval(
            child: localFileExists(avatarPath)
                ? Image.file(File(avatarPath!), fit: BoxFit.cover)
                : (photoUrl != null && photoUrl.trim().isNotEmpty)
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
        ),
        if (verified)
          const Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.verified, color: blue, size: 17),
          ),
      ],
    );
  }

  Widget friendUserTile({
    required FriendUserData user,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            userAvatar(
              username: user.username,
              photoUrl: user.photoUrl,
              avatarPath: user.avatarPath,
              verified: user.verified,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.role == UserRole.admin) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.admin_panel_settings,
                          color: blue,
                          size: 15,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget actionButton({
    required String label,
    required VoidCallback? onPressed,
    Color color = blue,
    bool outlined = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );

    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: shape,
        ),
        child: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: shape,
      ),
      child: Text(label),
    );
  }

  Widget friendsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.group,
        title: 'Log in required',
        text: 'Log in before using friends.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: friendshipsCollection()
          .where('userIds', arrayContains: firebaseUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];

        if (docs.isEmpty) {
          return const EmptyStateCard(
            icon: Icons.group_outlined,
            title: 'No friends yet',
            text: 'Use Find Users to send your first friend request.',
          );
        }

        return Column(
          children: [
            for (final doc in docs)
              FutureBuilder<FriendUserData?>(
                future: loadFriendUser(
                  friendUidFromFriendshipData(doc.data(), firebaseUser.uid),
                ),
                builder: (context, userSnapshot) {
                  final user = userSnapshot.data;

                  if (user == null || !user.canAppearInUserLists) {
                    return const SizedBox.shrink();
                  }

                  return friendUserTile(
                    user: user,
                    subtitle: user.name,
                    onTap: () => openUserProfile(
                      context,
                      uid: user.uid,
                      fallbackUsername: user.username,
                    ),
                    trailing: actionButton(
                      label: 'Remove',
                      color: Colors.redAccent,
                      outlined: true,
                      onPressed: () => removeFriend(user),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget requestsTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.mark_email_unread_outlined,
        title: 'Log in required',
        text: 'Log in before using friend requests.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Incoming requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('toUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.inbox_outlined,
                title: 'No incoming requests',
                text: 'Friend invites sent to you will appear here.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        userAvatar(username: request.fromUsername),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.fromUsername,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                request.fromName,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actionButton(
                          label: 'Accept',
                          onPressed: () => acceptRequest(request),
                        ),
                        const SizedBox(width: 6),
                        actionButton(
                          label: 'Decline',
                          color: Colors.redAccent,
                          outlined: true,
                          onPressed: () => declineRequest(request),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text(
          'Sent requests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendRequestsCollection()
              .where('fromUid', isEqualTo: firebaseUser.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            final requests =
                snapshot.data?.docs
                    .map((doc) => FriendRequestData.fromFirestore(doc))
                    .toList() ??
                const <FriendRequestData>[];

            if (requests.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.outbox_outlined,
                title: 'No sent requests',
                text: 'Requests you send will appear here until accepted.',
              );
            }

            return Column(
              children: [
                for (final request in requests)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        userAvatar(username: request.toUsername),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.toUsername,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                request.toName,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        actionButton(
                          label: 'Cancel',
                          color: Colors.redAccent,
                          outlined: true,
                          onPressed: () => cancelRequest(request),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget findUsersTab() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return const EmptyStateCard(
        icon: Icons.person_search,
        title: 'Log in required',
        text: 'Log in before finding friends.',
      );
    }

    return Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: (value) =>
              setState(() => searchText = value.trim().toLowerCase()),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: 'Search users',
            hintText: 'nickname or name',
            prefixIcon: const Icon(Icons.search, color: blue),
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: blue, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersCollection().orderBy('usernameKey').snapshots(),
          builder: (context, snapshot) {
            final users =
                snapshot.data?.docs
                    .map((doc) => FriendUserData.fromFirestore(doc))
                    .where((user) => user.canAppearInUserLists)
                    .where((user) => user.uid != firebaseUser.uid)
                    .where((user) {
                      if (searchText.isEmpty) {
                        return true;
                      }

                      return user.username.toLowerCase().contains(searchText) ||
                          user.name.toLowerCase().contains(searchText);
                    })
                    .toList() ??
                const <FriendUserData>[];

            if (users.isEmpty) {
              return const EmptyStateCard(
                icon: Icons.person_search,
                title: 'No users found',
                text: 'Try searching by nickname or name.',
              );
            }

            return Column(
              children: [
                for (final user in users)
                  FutureBuilder<String>(
                    future: friendStatusLabelForUser(
                      firebaseUser.uid,
                      user.uid,
                    ),
                    builder: (context, statusSnapshot) {
                      final status = statusSnapshot.data ?? 'loading';
                      final isFriend = status == 'friends';
                      final incoming = status == 'incoming';
                      final outgoing = status == 'outgoing';

                      return friendUserTile(
                        user: user,
                        subtitle: user.name,
                        onTap: () => openUserProfile(
                          context,
                          uid: user.uid,
                          fallbackUsername: user.username,
                        ),
                        trailing: incoming
                            ? actionButton(
                                label: 'Accept',
                                onPressed: () async {
                                  final doc = await friendRequestsCollection()
                                      .doc(
                                        friendRequestIdFor(
                                          user.uid,
                                          firebaseUser.uid,
                                        ),
                                      )
                                      .get();
                                  if (doc.exists) {
                                    await acceptRequest(
                                      FriendRequestData.fromFirestore(doc),
                                    );
                                  }
                                },
                              )
                            : actionButton(
                                label: isFriend
                                    ? 'Friends'
                                    : outgoing
                                    ? 'Sent'
                                    : status == 'loading'
                                    ? '...'
                                    : 'Add',
                                outlined: isFriend || outgoing,
                                onPressed:
                                    (isFriend ||
                                        outgoing ||
                                        status == 'loading')
                                    ? null
                                    : () => sendRequest(user),
                              ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<String> friendStatusLabelForUser(
    String currentUid,
    String otherUid,
  ) async {
    if (await areUsersFriends(currentUid, otherUid)) {
      return 'friends';
    }

    return await pendingRequestStatusBetweenUsers(currentUid, otherUid) ??
        'none';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Friends'),
          backgroundColor: Colors.black,
          foregroundColor: blue,
          bottom: const TabBar(
            indicatorColor: blue,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'Friends'),
              Tab(
                icon: Icon(Icons.mark_email_unread_outlined),
                text: 'Requests',
              ),
              Tab(icon: Icon(Icons.person_search), text: 'Find'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: friendsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: requestsTab(),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: findUsersTab(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfileData profile;
  final VoidCallback onEdit;

  const _ProfileHeader({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: blue.withValues(alpha: 0.5)),
                ),
                child: ClipOval(
                  child: localFileExists(profile.avatarPath)
                      ? Image.file(
                          File(profile.avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: Text(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : isNetworkUrl(profile.photoUrl)
                      ? Image.network(
                          profile.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: Text(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Text(
                            'CCS',
                            style: TextStyle(
                              color: blue,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: blue, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            profile.cityCountry,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _ProfileStatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: blue, size: 21),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}


class _GarageGalleryHeader extends StatefulWidget {
  final GarageCar car;

  const _GarageGalleryHeader({required this.car});

  @override
  State<_GarageGalleryHeader> createState() => _GarageGalleryHeaderState();
}

class _GarageGalleryHeaderState extends State<_GarageGalleryHeader> {
  int currentIndex = 0;

  List<String> get photos => widget.car.galleryPhotos;

  void openGallery(int index) {
    if (photos.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GaragePhotoGalleryScreen(
          car: widget.car,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentIndex >= photos.length) {
      currentIndex = photos.isEmpty ? 0 : photos.length - 1;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: garagePhotoAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () => openGallery(currentIndex),
                  child: photos.isEmpty
                      ? const _GaragePhotoFallback()
                      : garagePhotoImage(photos[currentIndex], fit: BoxFit.cover),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
                if (photos.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${currentIndex + 1}/${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 270),
                      child: Text(
                        widget.car.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (photos.length > 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              color: Colors.black,
              child: Row(
                children: [
                  for (var index = 0; index < photos.length; index++) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => currentIndex = index),
                        onLongPress: () => openGallery(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: currentIndex == index ? blue : Colors.white24,
                              width: currentIndex == index ? 2.2 : 1,
                            ),
                            boxShadow: currentIndex == index
                                ? [
                                    BoxShadow(
                                      color: blue.withValues(alpha: 0.36),
                                      blurRadius: 14,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              garagePhotoImage(photos[index], fit: BoxFit.cover),
                              if (currentIndex == index)
                                Container(
                                  decoration: BoxDecoration(
                                    color: blue.withValues(alpha: 0.16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index != photos.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class GaragePhotoGalleryScreen extends StatefulWidget {
  final GarageCar car;
  final int initialIndex;

  const GaragePhotoGalleryScreen({
    super.key,
    required this.car,
    required this.initialIndex,
  });

  @override
  State<GaragePhotoGalleryScreen> createState() => _GaragePhotoGalleryScreenState();
}

class _GaragePhotoGalleryScreenState extends State<GaragePhotoGalleryScreen> {
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex.clamp(0, widget.car.galleryPhotos.length - 1);
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          photos.isEmpty ? widget.car.name : '${widget.car.name}  ${currentIndex + 1}/${photos.length}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: photos.isEmpty
          ? const Center(child: _GaragePhotoFallback())
          : PageView.builder(
              controller: controller,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: garagePhotoImage(
                      photos[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _GarageCard extends StatelessWidget {
  final GarageCar car;
  final VoidCallback? onEdit;

  const _GarageCard({required this.car, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GarageGalleryHeader(car: car),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car.description,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
                if (onEdit != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit Garage'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ProfileSocialLinksSection extends StatelessWidget {
  const _ProfileSocialLinksSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserSettingsData>(
      valueListenable: userSettings,
      builder: (context, settings, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Social links',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _SocialLinkRow(
                icon: Icons.camera_alt,
                label: 'Instagram',
                value: settings.instagram,
              ),
              const SizedBox(height: 10),
              _SocialLinkRow(
                icon: Icons.music_note,
                label: 'TikTok',
                value: settings.tiktok,
              ),
              const SizedBox(height: 10),
              _SocialLinkRow(
                icon: Icons.send,
                label: 'Telegram',
                value: settings.telegram,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SocialLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SocialLinkRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;

    return InkWell(
      onTap: hasValue ? () => launchExternalUrl(context, value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, color: blue, size: 19),
            const SizedBox(width: 10),
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                hasValue ? value : 'Not added yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: hasValue ? blue : Colors.white54),
              ),
            ),
            if (hasValue) ...[
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new, color: Colors.white38, size: 15),
            ],
          ],
        ),
      ),
    );
  }
}

class _BuildChip extends StatelessWidget {
  final String label;

  const _BuildChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GarageCarPhoto extends StatefulWidget {
  final GarageCar car;

  const GarageCarPhoto({super.key, required this.car});

  @override
  State<GarageCarPhoto> createState() => _GarageCarPhotoState();
}

class _GarageCarPhotoState extends State<GarageCarPhoto> {
  final PageController controller = PageController();
  int currentIndex = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    if (photos.isEmpty) {
      return const _GaragePhotoFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: controller,
          itemCount: photos.length,
          onPageChanged: (index) => setState(() => currentIndex = index),
          itemBuilder: (context, index) {
            return garagePhotoImage(photos[index], fit: BoxFit.cover);
          },
        ),
        if (photos.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '${currentIndex + 1}/${photos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget garagePhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (localFileExists(source)) {
    return Image.file(
      File(source),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const _GaragePhotoFallback(),
    );
  }

  if (isNetworkUrl(source)) {
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const _GaragePhotoFallback(),
    );
  }

  return const _GaragePhotoFallback();
}


class _GaragePhotoFallback extends StatelessWidget {
  const _GaragePhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue, size: 54),
    );
  }
}

class _ProfileStyleSection extends StatelessWidget {
  final List<String> tags;

  const _ProfileStyleSection({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Garage tags',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (tags.isEmpty)
                const _SmallTag(label: 'No tags yet', icon: Icons.local_offer)
              else
                for (final tag in tags)
                  _SmallTag(label: tag, icon: Icons.local_offer),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSubmissionsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const _ProfileSubmissionsPreview({required this.spots});

  @override
  Widget build(BuildContext context) {
    final latest = spots.isEmpty ? null : spots.first;
    final pendingCount = spots
        .where((spot) => spot.status == SpotStatus.pending)
        .length;
    final liveCount = spots
        .where((spot) => spot.status == SpotStatus.approved)
        .length;
    final rejectedCount = spots
        .where((spot) => spot.status == SpotStatus.rejected)
        .length;
    final summary = spots.isEmpty
        ? 'No spots created yet.'
        : [
            if (pendingCount > 0)
              '$pendingCount pending review',
            if (liveCount > 0)
              '$liveCount live',
            if (rejectedCount > 0)
              '$rejectedCount rejected',
          ].join(' • ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Submissions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            style: const TextStyle(color: Colors.white54),
          ),
          if (latest != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                SpotPhoto(
                  spot: latest,
                  width: 64,
                  height: 64,
                  borderRadius: BorderRadius.circular(13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latest.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        latest.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 8),
                      _PendingBadge(status: latest.status),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSavedSpotsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const _ProfileSavedSpotsPreview({required this.spots});

  @override
  Widget build(BuildContext context) {
    final visibleSpots = spots.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Saved Spots',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${spots.length}',
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            spots.isEmpty
                ? 'Saved spots will appear here.'
                : 'Your bookmarked car spots.',
            style: const TextStyle(color: Colors.white54),
          ),
          if (visibleSpots.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final spot in visibleSpots) ...[
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SpotDetailScreen(spot: spot),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SpotPhoto(
                        spot: spot,
                        width: 54,
                        height: 54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              spot.cityCountry,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              if (spot != visibleSpots.last)
                Divider(color: Colors.white.withValues(alpha: 0.08)),
            ],
          ],
        ],
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = blue,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  final UserProfileData profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
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
    cityController = TextEditingController(text: widget.profile.cityCountry);
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
    bioController.dispose();
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  void queueUsernameAvailabilityCheck() {
    usernameAvailabilityDebounce?.cancel();

    final cleanUsername = cleanProfileUsername(usernameController.text);

    if (cleanUsername.length < 3) {
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

  void saveProfile() {
    if (!canSaveProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
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
        cityCountry: cityController.text.trim().isEmpty
            ? 'Riga, Latvia'
            : cityController.text.trim(),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
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
                                (currentUser.photoUrl?.trim().isNotEmpty ?? false))
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
                          : const Icon(Icons.add_a_photo, color: blue, size: 34),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tap to change avatar',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Profile info',
            children: [
              _CcsTextField(
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
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
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
              _CcsTextField(
                controller: cityController,
                label: 'Base',
                hint: 'Riga, Latvia',
                icon: Icons.location_city,
              ),
              const SizedBox(height: 14),
              _CcsTextField(
                controller: bioController,
                label: 'About you',
                hint: 'Short description',
                icon: Icons.notes,
                maxLines: 4,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Social links',
            children: [
              _CcsTextField(
                controller: instagramController,
                label: 'Instagram',
                hint: 'https://instagram.com/...',
                icon: Icons.camera_alt,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
                controller: tiktokController,
                label: 'TikTok',
                hint: 'https://tiktok.com/@...',
                icon: Icons.music_note,
                keyboardType: TextInputType.url,
              ),
              _CcsTextField(
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
              label: const Text('Save Profile'),
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

class EditGarageScreen extends StatefulWidget {
  final GarageCar? car;

  const EditGarageScreen({super.key, this.car});

  @override
  State<EditGarageScreen> createState() => _EditGarageScreenState();
}

class _EditGarageScreenState extends State<EditGarageScreen> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late List<String> photoPaths;

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    nameController = TextEditingController(text: car?.name ?? 'BMW E46 Coupe');
    descriptionController = TextEditingController(
      text:
          car?.description ??
          'Short description about your car, setup, and what content you shoot.',
    );
    photoPaths = [...(car?.galleryPhotos ?? const <String>[])].take(maxGaragePhotos).toList();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> chooseCarPhoto() async {
    if (photoPaths.length >= maxGaragePhotos) {
      return;
    }

    final path = await pickPhotoFromPhone(context);

    if (!mounted || path == null) {
      return;
    }

    setState(() => photoPaths = [...photoPaths, path].take(maxGaragePhotos).toList());
  }

  void removeCarPhoto(int index) {
    if (index < 0 || index >= photoPaths.length) {
      return;
    }

    setState(() => photoPaths = [...photoPaths]..removeAt(index));
  }

  void saveCar() {
    final cleanPhotos = photoPaths
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .take(maxGaragePhotos)
        .toList();

    Navigator.pop(
      context,
      GarageCar(
        name: nameController.text.trim().isEmpty
            ? 'Untitled car'
            : nameController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? 'Car profile.'
            : descriptionController.text.trim(),
        photoPath: cleanPhotos.isEmpty ? null : cleanPhotos.first,
        photoPaths: cleanPhotos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.car != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Garage' : 'Add Car'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Car photos',
            children: [
              _GaragePhotoPickerField(
                photoPaths: photoPaths,
                onAddPhoto: chooseCarPhoto,
                onRemovePhoto: removeCarPhoto,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Car info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Car name',
                hint: 'BMW E46 Coupe',
                icon: Icons.directions_car,
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'Tell people about your car, build, setup, and plans',
                icon: Icons.notes,
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: saveCar,
              icon: const Icon(Icons.check),
              label: Text(isEditing ? 'Save Garage' : 'Add Car'),
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

class _GaragePhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _GaragePhotoPickerField({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxGaragePhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photoPaths.isNotEmpty
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
                    borderRadius: BorderRadius.circular(14),
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
                      Text(
                        photoPaths.isEmpty
                            ? 'Upload photos'
                            : '${photoPaths.length}/$maxGaragePhotos photos selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        canAddMore
                            ? 'Add up to 4 car photos. The first photo becomes the garage cover.'
                            : 'Maximum 4 photos selected. First photo is the garage cover.',
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
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: garagePhotoImage(
                        photoPaths[index],
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? blue.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          index == 0 ? 'Cover' : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => onRemovePhoto(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController instagramController;
  late final TextEditingController tiktokController;
  late final TextEditingController telegramController;

  late bool reviewNotifications;
  late bool likeNotifications;
  late bool commentNotifications;
  late bool newSpotNotifications;
  late bool newMessageNotifications;
  late bool publicProfile;
  late bool showSavedSpots;
  late bool showGarage;

  @override
  void initState() {
    super.initState();
    final settings = userSettings.value;
    instagramController = TextEditingController(text: settings.instagram);
    tiktokController = TextEditingController(text: settings.tiktok);
    telegramController = TextEditingController(text: settings.telegram);
    reviewNotifications = settings.reviewNotifications;
    likeNotifications = settings.likeNotifications;
    commentNotifications = settings.commentNotifications;
    newSpotNotifications = settings.newSpotNotifications;
    newMessageNotifications = settings.newMessageNotifications;
    publicProfile = settings.publicProfile;
    showSavedSpots = settings.showSavedSpots;
    showGarage = settings.showGarage;
  }

  @override
  void dispose() {
    instagramController.dispose();
    tiktokController.dispose();
    telegramController.dispose();
    super.dispose();
  }

  Future<void> saveSettings() async {
    final settings = UserSettingsData(
      instagram: instagramController.text.trim(),
      tiktok: tiktokController.text.trim(),
      telegram: telegramController.text.trim(),
      reviewNotifications: reviewNotifications,
      likeNotifications: likeNotifications,
      commentNotifications: commentNotifications,
      newSpotNotifications: newSpotNotifications,
      newMessageNotifications: newMessageNotifications,
      publicProfile: publicProfile,
      showSavedSpots: showSavedSpots,
      showGarage: showGarage,
    );

    try {
      await saveSettingsToFirebase(settings);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Settings saved to your account.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Could not save settings: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Notifications',
            children: [
              _SettingsSwitchTile(
                icon: Icons.verified,
                title: 'Spot review updates',
                subtitle: 'Approved or rejected spot submissions',
                value: reviewNotifications,
                onChanged: (value) =>
                    setState(() => reviewNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.favorite,
                title: 'Likes on my spots',
                subtitle: 'When people like your approved spots',
                value: likeNotifications,
                onChanged: (value) => setState(() => likeNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.chat_bubble,
                title: 'Comments',
                subtitle: 'Future comments and community replies',
                value: commentNotifications,
                onChanged: (value) =>
                    setState(() => commentNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.map,
                title: 'New spots',
                subtitle: 'Fresh approved locations nearby',
                value: newSpotNotifications,
                onChanged: (value) =>
                    setState(() => newSpotNotifications = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.mark_chat_unread,
                title: 'Messages',
                subtitle: 'New direct and group messages',
                value: newMessageNotifications,
                onChanged: (value) =>
                    setState(() => newMessageNotifications = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Privacy',
            children: [
              _SettingsSwitchTile(
                icon: Icons.public,
                title: 'Public profile',
                subtitle: 'Let other drivers see your profile',
                value: publicProfile,
                onChanged: (value) => setState(() => publicProfile = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.bookmark,
                title: 'Show saved spots',
                subtitle: 'Display saved spots on your public profile later',
                value: showSavedSpots,
                onChanged: (value) => setState(() => showSavedSpots = value),
              ),
              _SettingsSwitchTile(
                icon: Icons.directions_car,
                title: 'Show garage',
                subtitle: 'Display your car builds on your profile',
                value: showGarage,
                onChanged: (value) => setState(() => showGarage = value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: saveSettings,
              icon: const Icon(Icons.check),
              label: const Text('Save Settings'),
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

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: blue,
        secondary: Icon(icon, color: blue),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}

class AdminUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final UserRole role;
  final bool verified;
  final bool banned;
  final int? bannedUntilMillis;
  final bool deleted;

  const AdminUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    required this.role,
    required this.verified,
    required this.banned,
    this.bannedUntilMillis,
    required this.deleted,
  });

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  String get statusLabel {
    if (deleted) {
      return 'Deleted';
    }

    return userBanLabel(
      banned: banned,
      bannedUntilMillis: bannedUntilMillis,
    );
  }

  factory AdminUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );

    return AdminUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      role: roleFromFirebase(data['role']),
      verified:
          roleFromFirebase(data['role']) == UserRole.admin ||
          data['verified'] == true,
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      deleted: data['deleted'] == true,
    );
  }
}

class AdminVerifiedUsersScreen extends StatelessWidget {
  const AdminVerifiedUsersScreen({super.key});

  Future<void> setVerifiedStatus(
    BuildContext context,
    AdminUserData user,
    bool verified,
  ) async {
    try {
      await usersCollection().doc(user.uid).set({
        'verified': verified,
        'verifiedUpdatedByUid': currentUser.uid,
        'verifiedUpdatedBy': currentUser.username,
        'verifiedUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (user.uid == currentUser.uid) {
        currentUser = AppUser(
          uid: currentUser.uid,
          name: currentUser.name,
          username: currentUser.username,
          email: currentUser.email,
          photoUrl: currentUser.photoUrl,
          bio: currentUser.bio,
          avatarPath: currentUser.avatarPath,
          role: currentUser.role,
          verified: verified || currentUser.role == UserRole.admin,
          city: currentUser.city,
          country: currentUser.country,
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not update verified status',
        error: error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verified Users'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersCollection().orderBy('usernameKey').snapshots(),
        builder: (context, snapshot) {
          final users =
              snapshot.data?.docs
                  .map((doc) => AdminUserData.fromFirestore(doc))
                  .where((user) => !user.deleted)
                  .toList() ??
              const <AdminUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Grant verified status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verified users can create and see verified-only spots.',
                style: TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (users.isEmpty)
                const EmptyStateCard(
                  icon: Icons.verified_user,
                  title: 'No users yet',
                  text: 'Users will appear here after they sign in.',
                )
              else
                for (final user in users) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: user.verified
                                ? blue.withValues(alpha: 0.16)
                                : Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            user.verified
                                ? Icons.verified
                                : Icons.person_outline,
                            color: user.verified ? blue : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      user.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (user.role == UserRole.admin) ...[
                                    const SizedBox(width: 6),
                                    const _SmallTag(
                                      label: 'Admin',
                                      icon: Icons.admin_panel_settings,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                user.email.isEmpty ? user.name : user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: user.verified,
                          activeThumbColor: blue,
                          onChanged: user.role == UserRole.admin
                              ? null
                              : (value) =>
                                    setVerifiedStatus(context, user, value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  Future<bool> canManageUser(BuildContext context, AdminUserData user) async {
    if (user.uid == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'You cannot manage your own admin account here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    if (user.role == UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Admin accounts cannot be banned or deleted here.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> banUser(
    BuildContext context,
    AdminUserData user, {
    Duration? duration,
  }) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    final bannedUntil = duration == null
        ? null
        : Timestamp.fromDate(DateTime.now().add(duration));

    try {
      await usersCollection().doc(user.uid).set({
        'banned': true,
        'bannedUntil': bannedUntil,
        'bannedByUid': currentUser.uid,
        'bannedBy': currentUser.username,
        'bannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              duration == null ? 'User banned.' : 'User temporarily banned.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(context, message: 'Could not ban user', error: error);
    }
  }

  Future<void> unbanUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'banned': false,
        'bannedUntil': FieldValue.delete(),
        'unbannedByUid': currentUser.uid,
        'unbannedBy': currentUser.username,
        'unbannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: blue,
            content: Text(
              'User unbanned.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not unban user',
        error: error,
      );
    }
  }

  Future<void> deleteUser(BuildContext context, AdminUserData user) async {
    if (!await canManageUser(context, user)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text('Delete user?'),
          content: Text(
            'This will remove @${user.username} from the users list.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await usersCollection().doc(user.uid).set({
        'deleted': true,
        'banned': true,
        'bannedUntil': null,
        'publicProfile': false,
        'photoUrl': '',
        'avatarPath': null,
        'bio': 'Profile removed.',
        'garage': <Object>[],
        'settings': const UserSettingsData(
          instagram: '',
          tiktok: '',
          telegram: '',
          reviewNotifications: false,
          likeNotifications: false,
          commentNotifications: false,
          newSpotNotifications: false,
          publicProfile: false,
          showSavedSpots: false,
          showGarage: false,
        ).toFirebase(),
        'deletedByUid': currentUser.uid,
        'deletedBy': currentUser.username,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              'User deleted.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
    } catch (error) {
      showAdminActionError(
        context,
        message: 'Could not delete user',
        error: error,
      );
    }
  }

  void handleUserAction(
    BuildContext context,
    AdminUserData user,
    String action,
  ) {
    switch (action) {
      case 'open':
        openUserProfile(
          context,
          uid: user.uid,
          fallbackUsername: user.username,
        );
        break;
      case 'ban_1d':
        banUser(context, user, duration: const Duration(days: 1));
        break;
      case 'ban_7d':
        banUser(context, user, duration: const Duration(days: 7));
        break;
      case 'ban_30d':
        banUser(context, user, duration: const Duration(days: 30));
        break;
      case 'ban_forever':
        banUser(context, user);
        break;
      case 'unban':
        unbanUser(context, user);
        break;
      case 'delete':
        deleteUser(context, user);
        break;
    }
  }

  Widget userTile(BuildContext context, AdminUserData user) {
    final statusColor = user.banActive
        ? Colors.redAccent
        : user.verified
        ? blue
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              user.banActive
                  ? Icons.block
                  : user.verified
                  ? Icons.verified
                  : Icons.person_outline,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => openUserProfile(
                context,
                uid: user.uid,
                fallbackUsername: user.username,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (user.role == UserRole.admin) ...[
                          const SizedBox(width: 6),
                          const _SmallTag(
                            label: 'Admin',
                            icon: Icons.admin_panel_settings,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email.isEmpty ? user.name : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      user.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: panel,
            iconColor: Colors.white70,
            onSelected: (action) => handleUserAction(context, user, action),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open',
                child: Text('Open profile'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'ban_1d',
                child: Text('Ban 1 day'),
              ),
              const PopupMenuItem(
                value: 'ban_7d',
                child: Text('Ban 7 days'),
              ),
              const PopupMenuItem(
                value: 'ban_30d',
                child: Text('Ban 30 days'),
              ),
              const PopupMenuItem(
                value: 'ban_forever',
                child: Text('Ban forever'),
              ),
              if (user.banned)
                const PopupMenuItem(
                  value: 'unban',
                  child: Text('Unban'),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete user',
                  style: TextStyle(color: Colors.redAccent),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersCollection().orderBy('usernameKey').snapshots(),
        builder: (context, snapshot) {
          final users =
              snapshot.data?.docs
                  .map((doc) => AdminUserData.fromFirestore(doc))
                  .where((user) => !user.deleted)
                  .toList() ??
              const <AdminUserData>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Users',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                users.isEmpty
                    ? 'No users yet.'
                    : '${users.length} user${users.length == 1 ? '' : 's'} in Firebase.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 18),
              if (users.isEmpty)
                const EmptyStateCard(
                  icon: Icons.people_outline,
                  title: 'No users yet',
                  text: 'Users will appear here after they sign in.',
                )
              else
                for (final user in users) ...[
                  userTile(context, user),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

enum AdminSpotFilter { pending, approved, rejected, all }

String adminSpotFilterLabel(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'Pending';
    case AdminSpotFilter.approved:
      return 'Approved';
    case AdminSpotFilter.rejected:
      return 'Rejected';
    case AdminSpotFilter.all:
      return 'All';
  }
}

List<CarSpot> adminSpotsForFilter(AdminSpotFilter filter) {
  final spots = reviewSpots.value;

  switch (filter) {
    case AdminSpotFilter.pending:
      return spots.where((spot) => spot.status == SpotStatus.pending).toList();
    case AdminSpotFilter.approved:
      return spots.where((spot) => spot.status == SpotStatus.approved).toList();
    case AdminSpotFilter.rejected:
      return spots.where((spot) => spot.status == SpotStatus.rejected).toList();
    case AdminSpotFilter.all:
      return spots;
  }
}

int adminSpotCount(AdminSpotFilter filter) {
  return adminSpotsForFilter(filter).length;
}

String adminEmptyTitle(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'No pending spots';
    case AdminSpotFilter.approved:
      return 'No approved spots';
    case AdminSpotFilter.rejected:
      return 'No rejected spots';
    case AdminSpotFilter.all:
      return 'No community spots yet';
  }
}

String adminEmptyText(AdminSpotFilter filter) {
  switch (filter) {
    case AdminSpotFilter.pending:
      return 'New user submitted spots will appear here first.';
    case AdminSpotFilter.approved:
      return 'Approved spots will appear here after moderation.';
    case AdminSpotFilter.rejected:
      return 'Rejected spots will appear here after moderation.';
    case AdminSpotFilter.all:
      return 'When users submit spots, they will appear in this admin panel.';
  }
}

Future<bool> confirmDeleteSpot(BuildContext context, CarSpot spot) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panel,
        title: const Text('Delete spot?'),
        content: Text(
          'This will remove "${spot.name}" from Firebase.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

void showAdminActionError(
  BuildContext context, {
  required String message,
  required Object error,
}) {
  if (!context.mounted) {
    return;
  }

  final code = error is FirebaseException ? error.code : error.toString();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(
        '$message: $code',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

Future<void> deleteAdminSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterDelete = false,
}) async {
  final confirmed = await confirmDeleteSpot(context, spot);

  if (!confirmed) {
    return;
  }

  try {
    await deleteSpotFromFirebase(spot);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'Spot deleted.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (popAfterDelete) {
      Navigator.pop(context);
    }
  } catch (error) {
    showAdminActionError(
      context,
      message: 'Could not delete spot',
      error: error,
    );
  }
}

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  AdminSpotFilter selectedFilter = AdminSpotFilter.pending;

  Widget filterChip(AdminSpotFilter filter) {
    final selected = selectedFilter == filter;
    final count = adminSpotCount(filter);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('${adminSpotFilterLabel(filter)} $count'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => selectedFilter = filter),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Admin Panel'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: reviewSpots,
        builder: (context, _, _) {
          final filteredSpots = adminSpotsForFilter(selectedFilter);
          final label = adminSpotFilterLabel(selectedFilter).toLowerCase();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text(
                'Admin Review',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                filteredSpots.isEmpty
                    ? 'No $label spots right now.'
                    : '${filteredSpots.length} $label spot${filteredSpots.length == 1 ? '' : 's'} in Firebase.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              const SizedBox(height: 16),
              _ProfileActionTile(
                icon: Icons.people_alt,
                title: 'Users',
                subtitle: 'Open profiles, ban, unban, or delete users',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.verified_user,
                title: 'Verified Users',
                subtitle: 'Grant or remove verified status',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminVerifiedUsersScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    filterChip(AdminSpotFilter.pending),
                    filterChip(AdminSpotFilter.approved),
                    filterChip(AdminSpotFilter.rejected),
                    filterChip(AdminSpotFilter.all),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (filteredSpots.isEmpty)
                EmptyStateCard(
                  icon: Icons.admin_panel_settings,
                  title: adminEmptyTitle(selectedFilter),
                  text: adminEmptyText(selectedFilter),
                )
              else
                for (final spot in filteredSpots) ...[
                  AdminSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class AdminSpotTile extends StatelessWidget {
  final CarSpot spot;

  const AdminSpotTile({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminSpotReviewScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 82,
              height: 82,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _AdminStatusBadge(status: spot.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: spot.addedByUid.trim().isEmpty
                            ? Text(
                                'Added by ${spot.addedBy}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38),
                              )
                            : InkWell(
                                onTap: () => openUserProfile(
                                  context,
                                  uid: spot.addedByUid,
                                  fallbackUsername: spot.addedBy,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                child: Text(
                                  'Added by @${spot.addedBy.replaceAll('@', '')}',
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
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit spot',
              onPressed: () => openAdminEditSpot(context, spot),
              icon: const Icon(Icons.edit_outlined, color: blue),
            ),
            IconButton(
              tooltip: 'Delete spot',
              onPressed: () => deleteAdminSpot(context, spot),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _AdminStatusBadge extends StatelessWidget {
  final SpotStatus status;

  const _AdminStatusBadge({required this.status});

  Color get color {
    switch (status) {
      case SpotStatus.pending:
        return blue;
      case SpotStatus.approved:
        return Colors.greenAccent;
      case SpotStatus.rejected:
        return Colors.redAccent;
    }
  }

  IconData get icon {
    switch (status) {
      case SpotStatus.pending:
        return Icons.hourglass_bottom;
      case SpotStatus.approved:
        return Icons.check_circle;
      case SpotStatus.rejected:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            spotStatusName(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}


Future<void> openAdminEditSpot(
  BuildContext context,
  CarSpot spot, {
  bool popAfterSave = false,
}) async {
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => AdminEditSpotScreen(spot: spot)),
  );

  if (saved == true && popAfterSave && context.mounted) {
    Navigator.pop(context);
  }
}

class AdminEditSpotScreen extends StatefulWidget {
  final CarSpot spot;

  const AdminEditSpotScreen({super.key, required this.spot});

  @override
  State<AdminEditSpotScreen> createState() => _AdminEditSpotScreenState();
}

class _AdminEditSpotScreenState extends State<AdminEditSpotScreen> {
  late final TextEditingController nameController;
  late final TextEditingController cityController;
  late final TextEditingController descriptionController;
  late final TextEditingController reelController;
  late final TextEditingController phoneController;
  late final TextEditingController instagramController;
  late final TextEditingController emailController;
  late String selectedCategory;
  late bool verifiedOnlySpot;
  late final List<String> existingPhotoUrls;
  final List<String> newPhotoPaths = [];
  late Map<int, OpeningHoursData> openingHours;
  SpotOwnerAssignment? selectedOwner;
  bool isSaving = false;

  int get totalPhotoCount => existingPhotoUrls.length + newPhotoPaths.length;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.spot.name);
    cityController = TextEditingController(text: widget.spot.cityCountry);
    descriptionController = TextEditingController(text: widget.spot.description);
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
    descriptionController.dispose();
    reelController.dispose();
    phoneController.dispose();
    instagramController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> addPhoto() async {
    if (totalPhotoCount >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Maximum 4 spot photos.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(context);
    if (!mounted || path == null || path.trim().isEmpty) {
      return;
    }

    if (newPhotoPaths.contains(path)) {
      return;
    }

    setState(() => newPhotoPaths.add(path));
  }

  void removeExistingPhotoAt(int index) {
    if (index < 0 || index >= existingPhotoUrls.length) {
      return;
    }

    setState(() => existingPhotoUrls.removeAt(index));
  }

  void removeNewPhotoAt(int index) {
    if (index < 0 || index >= newPhotoPaths.length) {
      return;
    }

    setState(() => newPhotoPaths.removeAt(index));
  }

  Future<void> saveSpot() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final cleanName = nameController.text.trim();
    final cleanCity = cityController.text.trim();
    final cleanDescription = descriptionController.text.trim();
    final cleanReel = reelController.text.trim();
    final cleanPhone = phoneController.text.trim();
    final cleanInstagram = instagramController.text.trim();
    final cleanEmail = emailController.text.trim();
    final supportsContacts = spotCategorySupportsContacts(selectedCategory);
    final owner = supportsContacts ? selectedOwner : null;

    if (firebaseUser == null) {
      showAdminActionError(
        context,
        message: 'Could not save spot',
        error: FirebaseException(
          plugin: 'firebase_auth',
          code: 'not-logged-in',
        ),
      );
      return;
    }

    if (widget.spot.id.trim().isEmpty) {
      showAdminActionError(
        context,
        message: 'Could not save spot',
        error: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'missing-spot-id',
        ),
      );
      return;
    }

    if (cleanName.isEmpty || cleanDescription.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot name and description are required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final finalPhotoUrls = <String>[...existingPhotoUrls];

      for (final localPhotoPath in newPhotoPaths) {
        final uploadIndex = finalPhotoUrls.length;
        final uploadedUrl = await uploadSpotPhoto(
          spotId: widget.spot.id,
          localPhotoPath: localPhotoPath,
          userId: firebaseUser.uid,
          photoIndex: uploadIndex,
        );
        finalPhotoUrls.add(uploadedUrl);
      }

      final updatedSpot = widget.spot.copyWith(
        name: cleanName,
        cityCountry: cleanCity.isEmpty ? widget.spot.cityCountry : cleanCity,
        description: cleanDescription,
        categories: [selectedCategory],
        reelLink: cleanReel,
        contactPhone: supportsContacts ? cleanPhone : '',
        contactInstagram: supportsContacts ? cleanInstagram : '',
        contactEmail: supportsContacts ? cleanEmail : '',
        openingHours: supportsContacts ? openingHours : const {},
        ownerUid: supportsContacts ? (owner?.uid ?? '') : '',
        ownerUsername: supportsContacts ? (owner?.username ?? '') : '',
        photoUrl: finalPhotoUrls.isEmpty ? '' : finalPhotoUrls.first,
        photoUrls: finalPhotoUrls,
        verifiedOnly: verifiedOnlySpot,
      );

      await spotsCollection().doc(widget.spot.id).update({
        'name': updatedSpot.name,
        'cityCountry': updatedSpot.cityCountry,
        'description': updatedSpot.description,
        'categories': updatedSpot.categories,
        'reelLink': updatedSpot.reelLink,
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'ownerUid': updatedSpot.ownerUid,
        'ownerUsername': updatedSpot.ownerUsername,
        'photoUrl': updatedSpot.photoUrl,
        'photoUrls': updatedSpot.photoUrls,
        'verifiedOnly': updatedSpot.verifiedOnly,
        'editedBy': currentUser.username,
        'editedByUid': currentUser.uid,
        'editedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      reviewSpots.value = reviewSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();
      submittedSpots.value = submittedSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();
      savedSpots.value = savedSpots.value
          .map((item) => isSameSpot(item, widget.spot) ? updatedSpot : item)
          .toList();

      await refreshFirebaseSpotsFromServer();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
            'Spot updated.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAdminActionError(
        context,
        message: 'Could not save spot',
        error: error,
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget photoThumb({
    required int index,
    required String label,
    required String source,
    required VoidCallback onRemove,
    required bool isLocal,
  }) {
    final image = isLocal
        ? Image.file(
            File(source),
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _SpotPhotoPlaceholder(
              width: 88,
              height: 88,
            ),
          )
        : Image.network(
            source,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _SpotPhotoPlaceholder(
              width: 88,
              height: 88,
            ),
          );

    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: index == 0
                  ? blue.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = totalPhotoCount < maxSpotGalleryPhotos;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Spot'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          _AddSpotSection(
            title: 'Basic info',
            children: [
              _CcsTextField(
                controller: nameController,
                label: 'Spot name',
                hint: 'Andrejsala Harbor',
                icon: Icons.place,
              ),
              _CcsTextField(
                controller: cityController,
                label: 'City / country',
                hint: 'Riga, Latvia',
                icon: Icons.location_city,
              ),
              _CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'What makes this spot good for car photos?',
                icon: Icons.notes,
                maxLines: 4,
              ),
              _CcsTextField(
                controller: reelController,
                label: 'Instagram / TikTok video link',
                hint: 'https://instagram.com/reel/...',
                icon: Icons.play_circle,
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (spotCategorySupportsContacts(selectedCategory)) ...[
            _AddSpotSection(
              title: 'Contacts',
              children: [
                _CcsTextField(
                  controller: phoneController,
                  label: 'Phone',
                  hint: '+371 20 000 000',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                _CcsTextField(
                  controller: instagramController,
                  label: 'Instagram',
                  hint: '@ccs.lv or https://instagram.com/ccs.lv',
                  icon: Icons.alternate_email,
                  keyboardType: TextInputType.url,
                ),
                _CcsTextField(
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
            _AddSpotSection(
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
          _AddSpotSection(
            title: 'Category',
            children: [
              _SpotCategoryDropdown(
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
            _AddSpotSection(
              title: 'Visibility',
              children: [
                _SettingsSwitchTile(
                  icon: Icons.verified_user,
                  title: 'Verified only',
                  subtitle:
                      'Only verified users and admins can see this spot after approval',
                  value: verifiedOnlySpot,
                  onChanged: (value) => setState(() => verifiedOnlySpot = value),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _AddSpotSection(
            title: 'Photos',
            children: [
              InkWell(
                onTap: canAddMore ? addPhoto : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: totalPhotoCount > 0
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
                          borderRadius: BorderRadius.circular(14),
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
                            Text(
                              totalPhotoCount == 0
                                  ? 'Upload photos'
                                  : '$totalPhotoCount/$maxSpotGalleryPhotos photos selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
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
              if (totalPhotoCount > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var index = 0; index < existingPhotoUrls.length; index++)
                      photoThumb(
                        index: index,
                        label: index == 0 ? 'Cover' : '${index + 1}',
                        source: existingPhotoUrls[index],
                        isLocal: false,
                        onRemove: () => removeExistingPhotoAt(index),
                      ),
                    for (var index = 0; index < newPhotoPaths.length; index++)
                      photoThumb(
                        index: existingPhotoUrls.length + index,
                        label: existingPhotoUrls.length + index == 0
                            ? 'Cover'
                            : '${existingPhotoUrls.length + index + 1}',
                        source: newPhotoPaths[index],
                        isLocal: true,
                        onRemove: () => removeNewPhotoAt(index),
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
              onPressed: isSaving ? null : saveSpot,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.save),
              label: Text(isSaving ? 'Saving...' : 'Save Changes'),
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

class AdminSpotReviewScreen extends StatelessWidget {
  final CarSpot spot;

  const AdminSpotReviewScreen({super.key, required this.spot});

  Future<void> approveSpot(BuildContext context) async {
    try {
      await updateSpotStatus(spot, SpotStatus.approved);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: Text(
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

  Future<void> rejectSpot(BuildContext context) async {
    try {
      await updateSpotStatus(spot, SpotStatus.rejected);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'Spot rejected.',
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Manage Spot'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Edit spot',
            onPressed: () => openAdminEditSpot(
              context,
              spot,
              popAfterSave: true,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
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
              _AdminStatusBadge(status: spot.status),
              const Spacer(),
              Flexible(
                child: spot.addedByUid.trim().isEmpty
                    ? Text(
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
                        child: Text(
                          'Added by @${spot.addedBy.replaceAll('@', '')}',
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
          Text(
            spot.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(spot.cityCountry, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          Text(
            spot.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (spot.verifiedOnly)
                _SmallTag(label: 'Verified only', icon: Icons.verified_user),
              for (final category in spot.categories)
                _SmallTag(label: category, icon: Icons.local_offer),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    rejectSpot(context);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
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
                    approveSpot(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => openAdminEditSpot(
                context,
                spot,
                popAfterSave: true,
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Spot'),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                deleteSpot(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Spot'),
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
        ],
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  final String title;
  final String text;

  const AppPage({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('CCS'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
