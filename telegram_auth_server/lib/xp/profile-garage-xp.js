const MIN_PROFILE_BIO_CHARS = 20;
const MIN_CAR_DESCRIPTION_CHARS = 20;

function evaluateProfileXp(userId, user) {
  const awards = [];
  const hasAvatar = hasText(user.photoUrl) || hasText(user.avatarPath);
  const bio = stringValue(user.bio);
  const hasBio = bio.length >= MIN_PROFILE_BIO_CHARS;
  const hasCity = hasText(user.city);
  const hasSocial = hasText(user.instagram) || hasText(user.telegram);
  const metadata = { userId };

  if (hasAvatar) {
    awards.push(profileAward(userId, 'profile.avatar', 'avatar', 50, metadata));
  }

  if (hasBio) {
    awards.push(
      profileAward(userId, 'profile.bio', 'bio', 40, {
        ...metadata,
        bioLength: bio.length,
      }),
    );
  }

  if (hasCity) {
    awards.push(profileAward(userId, 'profile.city', 'city', 30, metadata));
  }

  if (hasSocial) {
    awards.push(
      profileAward(userId, 'profile.social', 'instagram_or_telegram', 30, metadata),
    );
  }

  if (hasAvatar && hasBio && hasCity && hasSocial) {
    awards.push(profileAward(userId, 'profile.full', 'full_profile', 100, metadata));
  }

  return awards;
}

function evaluateFirstCarXp(userId, user) {
  const firstCar = firstGarageCar(user.garage);
  if (!firstCar) {
    return [];
  }

  const carName = stringValue(firstCar.name);
  const description = stringValue(firstCar.description);
  const photoCount = carPhotoCount(firstCar);
  const hasDescription = description.length >= MIN_CAR_DESCRIPTION_CHARS;
  const hasBuildInfo = hasText(firstCar.buildType) || hasText(firstCar.useType);
  const hasTags = Array.isArray(firstCar.tags)
    ? firstCar.tags.some((tag) => hasText(tag))
    : false;
  const hasFullCard =
    carName !== '' && hasDescription && photoCount >= 1 && hasBuildInfo && hasTags;
  const metadata = {
    userId,
    carName,
    photoCount,
  };
  const awards = [
    carAward(userId, 'garage.first_car', 'created', 50, metadata),
  ];

  if (photoCount >= 1) {
    awards.push(carAward(userId, 'garage.first_car_photo', 'first_photo', 50, metadata));
  }

  if (hasDescription) {
    awards.push(
      carAward(userId, 'garage.first_car_description', 'description', 50, {
        ...metadata,
        descriptionLength: description.length,
      }),
    );
  }

  if (photoCount >= 3) {
    awards.push(
      carAward(userId, 'garage.first_car_gallery', 'three_or_more_photos', 25, metadata),
    );
  }

  if (hasFullCard) {
    awards.push(carAward(userId, 'garage.first_car_full', 'full_card', 75, metadata));
  }

  return awards;
}

function profileAward(userId, action, stage, amount, metadata) {
  return {
    userId,
    action,
    objectType: 'profile',
    objectId: userId,
    stage,
    amount,
    metadata,
  };
}

function carAward(userId, action, stage, amount, metadata) {
  return {
    userId,
    action,
    objectType: 'garage_car',
    objectId: 'first_car',
    stage,
    amount,
    metadata,
  };
}

function firstGarageCar(value) {
  if (!Array.isArray(value) || value.length === 0) {
    return null;
  }

  const first = value[0];
  if (!first || typeof first !== 'object') {
    return null;
  }

  return first;
}

function carPhotoCount(car) {
  const photos = new Set();
  const cover = stringValue(car.photoPath);

  if (cover) {
    photos.add(cover);
  }

  if (Array.isArray(car.photoPaths)) {
    for (const item of car.photoPaths) {
      const photoPath = stringValue(item);
      if (photoPath) {
        photos.add(photoPath);
      }
    }
  }

  return photos.size;
}

function hasText(value) {
  return stringValue(value) !== '';
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

module.exports = {
  evaluateProfileXp,
  evaluateFirstCarXp,
};
