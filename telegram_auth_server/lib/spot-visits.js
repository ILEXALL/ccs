const crypto = require('node:crypto');

const VISIT_RADIUS_METERS = 100;
const MAX_SAMPLE_AGE_MS = 150000;
const millis = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
function coordinates(data = {}) {
  const lat = data.coordinates?.latitude ?? data.lat;
  const lng = data.coordinates?.longitude ?? data.lng;
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? {lat, lng} : null;
}
function distanceMeters(a, b) {
  const rad = Math.PI / 180;
  const h = Math.sin((b.lat - a.lat) * rad / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin((b.lng - a.lng) * rad / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
function rigaDay(now) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Riga', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date(now)).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

// Proximity is validated server-side; device GPS is not tamper-proof.
// No raw coordinates or a public attendance list are persisted here.
async function recordSpotVisit(db, userId, spotId, now = Date.now(), gpsFix = null) {
  if (typeof spotId !== 'string' || !spotId || spotId.includes('/') || spotId.length > 128) throw new Error('Invalid spot');
  const dayKey = rigaDay(now);
  const id = crypto.createHash('sha256').update(JSON.stringify([userId, spotId])).digest('hex');
  return db.runTransaction(async tx => {
    const userDoc = await tx.get(db.collection('users').doc(userId));
    const spotDoc = await tx.get(db.collection('spots').doc(spotId));
    const liveDoc = gpsFix == null ? await tx.get(db.collection('live_locations').doc(userId)) : null;
    const recordRef = db.collection('spot_visit_records').doc(id);
    const existing = await tx.get(recordRef);
    const user = userDoc.data(); const spot = spotDoc.data(); const live = gpsFix == null ? liveDoc.data() : {
      lat: gpsFix.latitude, lng: gpsFix.longitude, updatedAt: gpsFix.recordedAtMillis,
      expiresAt: Number(gpsFix.recordedAtMillis) + MAX_SAMPLE_AGE_MS,
      accuracy: gpsFix.accuracy, isMocked: gpsFix.isMocked,
    };
    if (gpsFix != null && (gpsFix.isMocked !== false || typeof gpsFix.accuracy !== 'number' ||
        typeof gpsFix.recordedAtMillis !== 'number')) throw new Error('Valid GPS location required');
    if (!user || user.deleted === true || user.banned === true) throw new Error('User unavailable');
    if (!spot || spot.deleted === true || spot.status !== 'approved' || spot.visibility === 'group' ||
        (spot.verifiedOnly === true && user.verified !== true && !['admin', 'moderator'].includes(user.role)) ||
        (spot.isTemporary === true && (millis(spot.expiresAt) <= now || millis(spot.startsAt) > now))) {
      throw new Error('Spot unavailable');
    }
    const position = coordinates(live || {}); const target = coordinates(spot);
    const sample = millis(live?.updatedAt);
    if (!position || !target || millis(live?.expiresAt) <= now || sample <= 0 || sample > now ||
        now - sample > MAX_SAMPLE_AGE_MS || live?.isMocked === true ||
        (typeof live?.accuracy === 'number' && (!Number.isFinite(live.accuracy) || live.accuracy < 0 || live.accuracy > 100)) ||
        distanceMeters(position, target) > VISIT_RADIUS_METERS) throw new Error('Fresh nearby location required');
    if (existing.exists) return {recorded: true, duplicate: true, dayKey};
    tx.create(recordRef, {userId, spotId, dayKey, recordedAtMillis: now,
      source: gpsFix == null ? 'shared_live_location' : 'gps_button', status: 'verified'});
    return {recorded: true, duplicate: false, dayKey};
  });
}
module.exports = {recordSpotVisit, coordinates, distanceMeters, rigaDay};
