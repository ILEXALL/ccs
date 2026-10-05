const {countryCode, profileCountry} = require('./private-groups');
const {canModerateCountry} = require('./regional-moderation');
const {createHash} = require('node:crypto');
const categories = new Set(['Drift','Photo','Meet','Drive','Service','Detailing','Wash','Store','Drag','Track','Activity','Off-road','Food','Scrap']);
function fail(message, status = 400) { throw Object.assign(new Error(message), {status}); }
function id(value) { return typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function text(value, max, required = false) {
  if (value == null && !required) return '';
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) fail('Invalid text');
  return value.trim();
}

async function createSpot(db, admin, uid, input, publicBase, now = Date.now()) {
  if (!input || !id(input.id)) fail('Invalid spot ID');
  if (Buffer.byteLength(JSON.stringify(input)) > 24000) fail('Spot request too large');
  const source = input.spot;
  if (!source || typeof source !== 'object' || Array.isArray(source)) fail('Invalid spot');
  const code = countryCode(source.countryCode);
  if (!code || code !== source.countryCode) fail('Invalid country');
  if (!Number.isFinite(source.lat) || Math.abs(source.lat) > 90 || !Number.isFinite(source.lng) || Math.abs(source.lng) > 180) fail('Invalid coordinates');
  if (!Array.isArray(source.categories) || source.categories.length !== 1 || !categories.has(source.categories[0])) fail('Invalid category');
  const groupIds = source.sharedGroupIds ?? [];
  if (!Array.isArray(groupIds) || groupIds.length > 8 || groupIds.some(value => !id(value)) || new Set(groupIds).size !== groupIds.length) fail('Invalid groups');
  const temporary = source.isTemporary === true;
  const visibility = groupIds.length ? 'group' : 'public';
  if (source.visibility !== visibility || (groupIds.length && (!temporary || source.verifiedOnly === true))) fail('Invalid audience');
  if (temporary && (!Number.isSafeInteger(source.startsAt) || !Number.isSafeInteger(source.expiresAt) ||
      source.expiresAt <= now || source.expiresAt <= source.startsAt || source.expiresAt - source.startsAt > 12 * 60 * 60 * 1000)) fail('Invalid event dates');
  if (temporary && source.showOnMapAt != null && (!Number.isSafeInteger(source.showOnMapAt) || source.showOnMapAt > source.startsAt)) fail('Invalid reveal date');
  const photos = source.photoUrls ?? [];
  const prefix = `${String(publicBase || '').replace(/\/+$/, '')}/users/${uid}/spot_photos/${input.id}/`;
  if (!Array.isArray(photos) || photos.length > 4 || photos.some(url => typeof url !== 'string' || !publicBase || !url.startsWith(prefix) || !/^[A-Za-z0-9_-]+\.jpg$/.test(url.slice(prefix.length)))) fail('Invalid photo ownership');
  const ref = db.collection('spots').doc(input.id);
  const fingerprint = createHash('sha256').update(JSON.stringify(input)).digest('hex');
  return db.runTransaction(async tx => {
    const refs = [db.doc(`users/${uid}`), db.doc(`account_deletions/${uid}`),
      db.doc(`users/${uid}/legal_acceptances/2026-09-24`), db.doc('app_config/main'), ref,
      ...groupIds.map(group => db.doc(`chats/${group}`))];
    const [actorDoc, deletion, consent, configDoc, existing, ...groups] = await tx.getAll(...refs);
    const actor = actorDoc.data() || {};
    const until = actor.bannedUntil?.toMillis?.() || 0;
    if (!actorDoc.exists || actor.deleted || deletion.exists || (actor.banned && (!until || until > now))) fail('Account is not active', 403);
    if (consent.data()?.termsVersion !== '2026-09-24' || !consent.data()?.acceptedAt?.toMillis) fail('Accept the current Terms of Use first', 403);
    const config = configDoc.data() || {};
    if ((config.bannedCountryCodes || []).includes(code) || (config.bannedCountryKeys || []).includes(code.toLowerCase()) ||
        (config.bannedCountryKeys || []).includes(String(actor.country || '').toLowerCase())) fail('Country is unavailable', 403);
    for (const group of groups) {
      const data = group.data() || {};
      if (!group.exists || data.isGroup !== true || !(data.memberIds || []).includes(uid) || (data.bannedMemberIds || []).includes(uid)) fail('Group membership required', 403);
    }
    if (existing.exists) {
      if (existing.data().addedByUid !== uid || existing.data().creationRequestHash !== fingerprint) fail('Spot ID already exists', 409);
      return {id: input.id, status: existing.data().status};
    }
    const staff = canModerateCountry(actor, code);
    if (source.verifiedOnly === true && !(actor.verified || actor.role === 'admin' || actor.role === 'moderator')) fail('Verification required', 403);
    let owner = null;
    if (source.ownerUid) {
      if (!staff || !id(source.ownerUid)) fail('Cannot assign an owner', 403);
      owner = (await tx.get(db.doc(`users/${source.ownerUid}`))).data();
      if (!owner || owner.deleted || owner.banned) fail('Invalid owner');
    }
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const status = staff ? 'approved' : 'pending';
    const data = {
      name: text(source.name, 120, true), description: text(source.description, 4000),
      cityCountry: text(source.cityCountry, 200, true), countryCode: code,
      lat: source.lat, lng: source.lng, coordinates: new admin.firestore.GeoPoint(source.lat, source.lng),
      categories: source.categories, photoUrls: photos, photoUrl: photos[0] || '',
      visibility, sharedGroupIds: groupIds,
      sharedGroups: groups.map(group => ({id: group.id, name: group.data().name || 'Group', avatarUrl: group.data().avatarUrl || group.data().photoUrl || ''})),
      addedByUid: uid, addedBy: actor.username || actor.name || 'Driver', status,
      verifiedOnly: source.verifiedOnly === true, isTemporary: temporary,
      startsAt: temporary ? admin.firestore.Timestamp.fromMillis(source.startsAt) : null,
      expiresAt: temporary ? admin.firestore.Timestamp.fromMillis(source.expiresAt) : null,
      showOnMapAt: temporary && source.showOnMapAt != null ? admin.firestore.Timestamp.fromMillis(source.showOnMapAt) : null,
      ownerUid: owner ? source.ownerUid : '', ownerUsername: owner?.username || '',
      likeCount: 0, commentCount: 0, rating: 0, rejectionReason: '',
      lowCarFriendly: false, bestTime: 'Not reviewed', parking: 'Not reviewed', roadQuality: 'Not reviewed',
      policeRisk: 'Not reviewed', traffic: 'Not reviewed', lighting: 'Not reviewed', crowd: 'Not reviewed',
      createdAt: timestamp, updatedAt: timestamp, creationRequestHash: fingerprint,
    };
    for (const field of ['reelLink', 'contactPhone', 'contactInstagram', 'contactEmail']) data[field] = text(source[field], 1000);
    const hours = source.openingHours ?? {};
    if (!hours || Array.isArray(hours) || typeof hours !== 'object' || JSON.stringify(hours).length > 4000) fail('Invalid opening hours');
    data.openingHours = hours;
    tx.create(ref, data);
    for (const group of groupIds) tx.set(db.doc(`chats/${group}/spot_links/${input.id}`), {spotId: input.id, authorUid: uid, published: status === 'approved'});
    if (temporary) tx.create(db.doc(`forum_topics/temporary_spot_${input.id}`), {
      visibility, sharedGroupIds: groupIds, sharedGroups: data.sharedGroups, title: data.name,
      countryCode: code, authorCountryCode: profileCountry(actor), country: actor.country || '',
      category: 'Meets & Events', categoryId: 'meets_events', description: text(input.topicDescription ?? data.description, 4000),
      avatarUrl: data.photoUrl, authorId: uid, authorName: data.addedBy, authorRole: actor.role || 'user',
      authorVerified: actor.verified === true, authorGlobalChatModerator: false, authorGlobalModerator: false,
      repliesCount: 0, isPinned: false, status, rejectionReason: null,
      reviewedBy: staff ? uid : null, reviewedAt: staff ? timestamp : null,
      createdAt: timestamp, lastReplyAt: timestamp, source: 'temporary_spot', isSpotTopic: true,
      spotId: input.id, temporarySpotId: input.id, temporarySpotStartsAt: data.startsAt,
      temporarySpotExpiresAt: data.expiresAt, autoExpiresAt: data.expiresAt,
    });
    return {id: input.id, status};
  });
}
module.exports = {createSpot};
