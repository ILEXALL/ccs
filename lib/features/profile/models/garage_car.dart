import 'package:ccs_app/core/config/app_config.dart' show maxGaragePhotos;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase, stringListFromFirebase;

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
    final nextPhotoPath =
        photoPath ??
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
      name: stringFromFirebase(data['name'], 'Untitled car'),
      description: stringFromFirebase(data['description'], 'Car profile.'),
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
  return const [];
}

bool isLegacyDefaultGarageCar(GarageCar car) {
  return car.name.trim() == 'BMW E46 Coupe' &&
      car.description.trim() ==
          'Night drive setup for city shoots and clean street parking spots.' &&
      car.galleryPhotos.isEmpty &&
      car.buildType.trim().isEmpty &&
      car.useType.trim().isEmpty &&
      car.tags.isEmpty;
}

List<GarageCar> garageCarsFromFirebase(Object? value) {
  if (value is List) {
    final cars = value
        .map(GarageCar.fromFirebase)
        .where((car) => !isLegacyDefaultGarageCar(car))
        .toList();

    if (cars.isNotEmpty) {
      return cars;
    }
  }

  return const [];
}
