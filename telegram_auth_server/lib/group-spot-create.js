const {createHash} = require('node:crypto');
const {countryCode, profileCountry} = require('./private-groups');
const {canModerateCountry} = require('./regional-moderation');
const {TERMS_VERSION} = require('./media-uploads');
const fail = (status, message) => { throw Object.assign(new Error(message), {status}); };
const idValid = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,200}$/.test(id);
const dateValid = value => Number.isSafeInteger(value) && value >= 0 && value < 253402300800000;

function groupSpotInput(body, publicBaseUrl, now) {
  const {spotId, spot: input, topicDescription = ''} = body || {};
  if (!idValid(spotId) || !input || typeof input !== 'object' || Array.isArray(input)) fail(400, 'Invalid spot');
  const ids = input.sharedGroupIds;
  if (!Array.isArray(ids) || !ids.length || ids.length > 8 || ids.some(id => !idValid(id)) || new Set(ids).size !== ids.length) fail(400, 'Choose one to eight groups');
  if (input.visibility !== 'group' || input.isTemporary !== true || input.verifiedOnly === true) fail(400, 'Group spots must be temporary');
  const code = countryCode(input.countryCode);
  if (!code || code !== input.countryCode) fail(400, 'Unsupported country');
  if (!['pending', 'approved'].includes(input.status)) fail(400, 'Invalid status');
  if (![input.lat, input.lng, input.startsAt, input.expiresAt].every(Number.isFinite) ||
      !dateValid(input.startsAt) || !dateValid(input.expiresAt) ||
      Math.abs(input.lat) > 90 || Math.abs(input.lng) > 180 || input.expiresAt <= now ||
      input.expiresAt <= input.startsAt || input.expiresAt - input.startsAt > 12 * 3600000 ||
      (input.showOnMapAt != null && (!dateValid(input.showOnMapAt) || input.showOnMapAt > input.startsAt))) fail(400, 'Invalid location or event dates');
  const strings = {name: 120, cityCountry: 200, description: 4000, reelLink: 1500,
    contactPhone: 100, contactInstagram: 200, contactEmail: 200, bestTime: 100,
    parking: 100, roadQuality: 100, policeRisk: 100, traffic: 100, lighting: 100, crowd: 100};
  const spot = {};
  for (const [key, limit] of Object.entries(strings)) {
    const value = input[key] ?? '';
    if (typeof value !== 'string' || value.length > limit) fail(400, `Invalid ${key}`);
    spot[key] = value;
  }
  if (!spot.name.trim() || !spot.cityCountry.trim()) fail(400, 'Name and location are required');
  if (typeof topicDescription !== 'string' || topicDescription.length > 4000) fail(400, 'Invalid topic description');
  if (!Array.isArray(input.categories) || !input.categories.length || input.categories.length > 20 ||
      input.categories.some(value => typeof value !== 'string' || !value || value.length > 80)) fail(400, 'Invalid categories');
  const photos = input.photoUrls;
  if (!publicBaseUrl) fail(503, 'Storage configuration unavailable');
  if (!Array.isArray(photos) || !photos.length || photos.length > 4 ||
      photos.some(url => typeof url !== 'string' || url.length > 1500)) fail(400, 'Invalid photos');
  if (input.photoUrl !== photos[0]) fail(400, 'Invalid main photo');
  // Opening hours are optional structured UI data, never authorization fields.
  if (input.openingHours != null && (typeof input.openingHours !== 'object' || Array.isArray(input.openingHours) ||
      JSON.stringify(input.openingHours).length > 8000)) fail(400, 'Invalid opening hours');
  return {spotId, topicDescription, spot: {...spot, categories: input.categories, photoUrl: photos[0], photoUrls: photos,
    countryCode: code, lat: input.lat, lng: input.lng, startsAt: input.startsAt, expiresAt: input.expiresAt,
    showOnMapAt: input.showOnMapAt ?? null, openingHours: input.openingHours ?? {}, lowCarFriendly: input.lowCarFriendly === true,
    sharedGroupIds: ids, visibility: 'group', isTemporary: true, verifiedOnly: false, status: input.status}};
}

async function createGroupSpot({db, firestore, uid, body, publicBaseUrl, now = Date.now}) {
  const input = groupSpotInput(body, publicBaseUrl, now());
  const {spotId, spot} = input;
  const prefix = `${publicBaseUrl.replace(/\/+$/, '')}/spots/${spotId}/users/${uid}/`;
  if (spot.photoUrls.some(url => !url.startsWith(prefix) || url.slice(prefix.length).includes('..') || /[?#%]/.test(url.slice(prefix.length)))) fail(403, 'Use photos uploaded by this account');
  const fingerprint = createHash('sha256').update(JSON.stringify(input)).digest('hex');
  return db.runTransaction(async tx => {
    const ref = db.doc(`spots/${spotId}`);
    const [actorDoc, deletion, consent, configDoc, reservation, existing, ...groups] = await tx.getAll(
      db.doc(`users/${uid}`), db.doc(`account_deletions/${uid}`),
      db.doc(`users/${uid}/legal_acceptances/${TERMS_VERSION}`), db.doc('app_config/main'),
      db.doc(`media_spot_reservations/${spotId}`), ref,
      ...spot.sharedGroupIds.map(id => db.doc(`chats/${id}`)));
    const actor = actorDoc.data(), config = configDoc.data() || {};
    if (!actor || actor.deleted === true || actor.banned === true || deletion.exists) fail(403, 'Account unavailable');
    if (consent.data()?.termsVersion !== TERMS_VERSION) fail(403, 'Accept the current terms');
    if (reservation.data()?.uid !== uid) fail(403, 'Upload the spot photos before publishing');
    if (existing.exists) {
      if (existing.data().addedByUid === uid && existing.data().serverCreationHash === fingerprint) return {spotId, status: existing.data().status};
      fail(409, 'This spot ID is already in use');
    }
    if ((config.bannedCountryCodes || []).includes(spot.countryCode) ||
        (config.bannedCountryKeys || []).includes(spot.countryCode.toLowerCase()) ||
        (config.bannedCountryKeys || []).includes(String(actor.country || '').toLowerCase())) fail(403, 'Region unavailable');
    if (spot.status === 'approved' && !canModerateCountry(actor, spot.countryCode)) fail(403, 'Moderation required');
    for (const group of groups) {
      const data = group.data();
      if (!data || data.isGroup !== true || !(data.memberIds || []).includes(uid) || (data.bannedMemberIds || []).includes(uid)) fail(403, 'Group membership required');
    }
    const sharedGroups = groups.map(group => ({id: group.id, name: String(group.data().name || ''),
      avatarUrl: String(group.data().avatarUrl || group.data().photoUrl || '')}));
    const stamp = firestore.FieldValue.serverTimestamp();
    const startsAt = firestore.Timestamp.fromMillis(spot.startsAt), expiresAt = firestore.Timestamp.fromMillis(spot.expiresAt);
    const authorName = actor.username || 'driver';
    tx.create(ref, {...spot, coordinates: new firestore.GeoPoint(spot.lat, spot.lng), startsAt, expiresAt,
      showOnMapAt: spot.showOnMapAt == null ? null : firestore.Timestamp.fromMillis(spot.showOnMapAt), sharedGroups,
      addedByUid: uid, addedBy: authorName, ownerUid: '', ownerUsername: '', likeCount: 0, commentCount: 0,
      rejectionReason: '', serverCreationHash: fingerprint, createdAt: stamp, updatedAt: stamp});
    tx.create(db.doc(`forum_topics/temporary_spot_${spotId}`), {visibility: 'group', sharedGroupIds: spot.sharedGroupIds,
      sharedGroups, title: spot.name, countryCode: spot.countryCode, authorCountryCode: profileCountry(actor) || 'LV',
      country: actor.country || '', category: 'Meets & Events', categoryId: 'meets_events', description: input.topicDescription,
      avatarUrl: spot.photoUrl, authorId: uid, authorName, authorRole: actor.role || 'user',
      authorVerified: actor.verified === true || ['admin', 'moderator'].includes(actor.role),
      authorGlobalChatModerator: false, authorGlobalModerator: false, repliesCount: 0, isPinned: false,
      status: spot.status, rejectionReason: null, reviewedBy: spot.status === 'approved' ? uid : null,
      reviewedAt: spot.status === 'approved' ? stamp : null, createdAt: stamp, lastReplyAt: stamp,
      source: 'temporary_spot', isSpotTopic: true, spotId, temporarySpotId: spotId,
      temporarySpotStartsAt: startsAt, temporarySpotExpiresAt: expiresAt, autoExpiresAt: expiresAt});
    for (const group of groups) tx.create(group.ref.collection('spot_links').doc(spotId), {
      spotId, authorUid: uid, published: spot.status === 'approved',
    });
    return {spotId, status: spot.status};
  });
}
module.exports = {createGroupSpot, groupSpotInput};
