const MIN_NORMAL_DESCRIPTION_CHARS = 20;

function shouldAwardSpotApprovalXp(before, after) {
  if (!after || after.status !== 'approved' || after.isTemporary === true) {
    return false;
  }

  return !before || before.status !== 'approved';
}

function evaluatePermanentSpotApprovalXp(spotId, spot) {
  if (spot.status !== 'approved' || spot.isTemporary === true) {
    return [];
  }

  const userId = stringValue(spot.addedByUid) || stringValue(spot.ownerUid);
  if (!userId) {
    return [];
  }

  const description = stringValue(spot.description);
  const photoCount = spotPhotoCount(spot);
  const hasReel = stringValue(spot.reelLink) !== '';
  const metadata = {
    spotId,
    spotName: stringValue(spot.name),
    isTemporary: false,
  };

  const awards = [
    {
      userId,
      action: 'spot.approved',
      objectType: 'spot',
      objectId: spotId,
      stage: 'published',
      amount: 50,
      metadata,
    },
  ];

  if (description.length >= MIN_NORMAL_DESCRIPTION_CHARS) {
    awards.push({
      userId,
      action: 'spot.description',
      objectType: 'spot',
      objectId: spotId,
      stage: 'normal_description',
      amount: 15,
      metadata: {
        ...metadata,
        descriptionLength: description.length,
      },
    });
  }

  if (photoCount >= 1) {
    awards.push({
      userId,
      action: 'spot.photo',
      objectType: 'spot',
      objectId: spotId,
      stage: 'first_photo',
      amount: 25,
      metadata: {
        ...metadata,
        photoCount,
      },
    });
  }

  if (photoCount >= 3 || hasReel) {
    awards.push({
      userId,
      action: 'spot.media_bundle',
      objectType: 'spot',
      objectId: spotId,
      stage: 'three_photos_or_reel',
      amount: 10,
      metadata: {
        ...metadata,
        photoCount,
        hasReel,
      },
    });
  }

  return awards;
}

function spotPhotoCount(spot) {
  const urls = new Set();
  const primaryPhoto = stringValue(spot.photoUrl);

  if (primaryPhoto) {
    urls.add(primaryPhoto);
  }

  if (Array.isArray(spot.photoUrls)) {
    for (const item of spot.photoUrls) {
      const photoUrl = stringValue(item);
      if (photoUrl) {
        urls.add(photoUrl);
      }
    }
  }

  return urls.size;
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

module.exports = {
  shouldAwardSpotApprovalXp,
  evaluatePermanentSpotApprovalXp,
  spotPhotoCount,
};
