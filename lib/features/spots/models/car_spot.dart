import 'package:ccs_app/core/time/trusted_clock.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        intFromFirebase,
        nullableTimestampMillisFromFirebase,
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show safeLatLngFromFirestoreCoordinates;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData, openingHoursFromFirebase;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategorySupportsContacts;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusFromFirebase;
import 'package:ccs_app/shared/models/countries.dart'
    show countryIsoCode, countryNamesByIso, spotCountryFromCityCountry;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

class CarSpot {
  final String id;
  final String name;
  final String cityCountry;
  final String countryCode;
  final LatLng coordinates;
  final String description;
  final List<String> categories;
  final int likeCount;
  final int commentCount;
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
  final int updatedAtMillis;
  final String visibility;
  final List<String> sharedGroupIds;
  final List<Map<String, dynamic>> sharedGroups;
  bool get isGroupSpot => visibility == "group";
  final bool isTemporary;
  final int? startsAtMillis;
  final int? expiresAtMillis;
  final int? showOnMapAtMillis;
  final bool verifiedOnly;
  final String rejectionReason;
  final String reviewedBy, reviewedByUid;

  const CarSpot({
    this.id = '',
    required this.name,
    required this.cityCountry,
    this.countryCode = '',
    required this.coordinates,
    required this.description,
    required this.categories,
    this.likeCount = 0,
    this.commentCount = 0,
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
    this.updatedAtMillis = 0,
    this.visibility = "public",
    this.sharedGroupIds = const [],
    this.sharedGroups = const [],
    this.isTemporary = false,
    this.startsAtMillis,
    this.expiresAtMillis,
    this.showOnMapAtMillis,
    this.verifiedOnly = false,
    this.rejectionReason = '',
    this.reviewedBy = '',
    this.reviewedByUid = '',
  });

  CarSpot copyWith({
    String? id,
    String? name,
    String? cityCountry,
    String? countryCode,
    LatLng? coordinates,
    String? description,
    List<String>? categories,
    int? likeCount,
    int? commentCount,
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
    int? updatedAtMillis,
    bool? isTemporary,
    int? startsAtMillis,
    int? expiresAtMillis,
    int? showOnMapAtMillis,
    bool? verifiedOnly,
    String? rejectionReason,
    String? reviewedBy,
    String? reviewedByUid,
    bool clearTemporarySchedule = false,
    bool clearTemporaryMapReveal = false,
  }) {
    return CarSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      cityCountry: cityCountry ?? this.cityCountry,
      countryCode: countryCode ?? this.countryCode,
      coordinates: coordinates ?? this.coordinates,
      description: description ?? this.description,
      categories: categories ?? this.categories,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
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
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      visibility: visibility,
      sharedGroupIds: sharedGroupIds,
      sharedGroups: sharedGroups,
      isTemporary: isTemporary ?? this.isTemporary,
      startsAtMillis: clearTemporarySchedule
          ? null
          : startsAtMillis ?? this.startsAtMillis,
      expiresAtMillis: clearTemporarySchedule
          ? null
          : expiresAtMillis ?? this.expiresAtMillis,
      showOnMapAtMillis: clearTemporarySchedule || clearTemporaryMapReveal
          ? null
          : showOnMapAtMillis ?? this.showOnMapAtMillis,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedByUid: reviewedByUid ?? this.reviewedByUid,
    );
  }

  bool get hasTemporaryWindow =>
      isTemporary && startsAtMillis != null && expiresAtMillis != null;

  String get effectiveCountryCode {
    final storedCode = countryCode.trim().toUpperCase();
    if (countryNamesByIso.containsKey(storedCode)) {
      return storedCode;
    }
    return countryIsoCode(spotCountryFromCityCountry(cityCountry)) ?? '';
  }

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
        (trustedClock.nowMillis ?? 0) >= expiresAt;
  }

  int? get effectiveShowOnMapAtMillis {
    if (!hasTemporaryWindow) {
      return null;
    }

    final customReveal = showOnMapAtMillis;
    if (customReveal != null) {
      return customReveal;
    }

    // Temporary spots should become visible on the map as soon as they are
    // approved/published. The old fallback revealed the location at midnight
    // on the event day, which made upcoming temporary spots look missing.
    return createdAtMillis > 0 ? createdAtMillis : 0;
  }

  bool get isTemporaryActiveNow {
    if (!hasTemporaryWindow) {
      return false;
    }

    final now = trustedClock.nowMillis;
    if (now == null) return false;
    return now >= startsAtMillis! && now < expiresAtMillis!;
  }

  bool get isTemporaryUpcomingOnMap {
    if (!hasTemporaryWindow) {
      return false;
    }

    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return false;
    }

    final now = trustedClock.nowMillis;
    if (now == null) return false;
    return now >= revealAt && now < startsAtMillis! && now < expiresAtMillis!;
  }

  bool get isTemporaryLocationAvailableNow {
    if (!hasTemporaryWindow) {
      return !isTemporary;
    }

    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return false;
    }

    final now = trustedClock.nowMillis;
    if (now == null) return false;
    return now >= revealAt && now < expiresAtMillis!;
  }

  bool get isTemporaryMapVisibleNow => isTemporaryLocationAvailableNow;

  bool get isVisibleOnMapNow {
    if (!isTemporary) {
      return true;
    }

    return isTemporaryMapVisibleNow;
  }

  bool get isVisibleNow {
    if (!isTemporary) {
      return true;
    }

    return hasTemporaryWindow && !isExpired;
  }

  String get temporaryStartsAtLabel {
    final startsAt = startsAtMillis;
    if (startsAt == null) {
      return '';
    }

    return '${trText('Starts at')} ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(startsAt))}';
  }

  String get temporaryStartingAtLabel {
    final startsAt = startsAtMillis;
    if (startsAt == null) {
      return '';
    }

    return '${trText('Starting at')} ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(startsAt))}';
  }

  String get temporaryLocationAvailableAtLabel {
    final revealAt = effectiveShowOnMapAtMillis;
    if (revealAt == null) {
      return '';
    }

    if (isTemporaryLocationAvailableNow) {
      return trText('Location available');
    }

    final revealDate = DateTime.fromMillisecondsSinceEpoch(revealAt);
    return '${trText('Location will be available at')} ${formatShortDateTime(revealDate)}';
  }

  String get temporaryEndsAtLabel {
    final expiresAt = expiresAtMillis;
    if (expiresAt == null) {
      return '';
    }

    return '${trText('Ends at')} ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(expiresAt))}';
  }

  String get temporaryTodayLabel {
    return isTemporaryActiveNow ? temporaryEndsAtLabel : temporaryStartsAtLabel;
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
    final coordinates = safeLatLngFromFirestoreCoordinates(
      data['coordinates'],
      data['lat'],
      data['lng'],
    );

    return CarSpot(
      id: doc.id,
      name: stringFromFirebase(data['name'], 'Untitled spot'),
      cityCountry: stringFromFirebase(data['cityCountry'], 'Riga, Latvia'),
      countryCode: stringFromFirebase(data['countryCode'], ''),
      coordinates: coordinates,
      description: stringFromFirebase(
        data['description'],
        'Submitted community car spot.',
      ),
      categories: stringListFromFirebase(data['categories'], const ['Photo']),
      likeCount: math.max(0, intFromFirebase(data['likeCount'], 0)),
      commentCount: math.max(0, intFromFirebase(data['commentCount'], 0)),
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
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      visibility: stringFromFirebase(data['visibility'], 'public'),
      sharedGroupIds: stringListFromFirebase(data['sharedGroupIds'], const []),
      sharedGroups:
          (data['sharedGroups'] is List
                  ? data['sharedGroups'] as List
                  : const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
      isTemporary: data['isTemporary'] == true,
      startsAtMillis: nullableTimestampMillisFromFirebase(data['startsAt']),
      expiresAtMillis: nullableTimestampMillisFromFirebase(data['expiresAt']),
      showOnMapAtMillis: nullableTimestampMillisFromFirebase(
        data['showOnMapAt'],
      ),
      verifiedOnly: data['verifiedOnly'] == true,
      rejectionReason: stringFromFirebase(data['rejectionReason'], ''),
      reviewedBy: stringFromFirebase(data['reviewedBy'], ''),
      reviewedByUid: stringFromFirebase(data['reviewedByUid'], ''),
    );
  }
}

bool isSameSpot(CarSpot first, CarSpot second) {
  if (first.id.isNotEmpty && second.id.isNotEmpty) {
    return first.id == second.id;
  }

  return first.name == second.name && first.addedBy == second.addedBy;
}

CarSpot spotWithCounterDelta(
  CarSpot spot, {
  int likeDelta = 0,
  int commentDelta = 0,
}) {
  return spot.copyWith(
    likeCount: math.max(0, spot.likeCount + likeDelta),
    commentCount: math.max(0, spot.commentCount + commentDelta),
    updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
  );
}
