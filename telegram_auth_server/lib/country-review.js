const { admin, db } = require('./firebase-admin');
const { countryCode: normalizeCountry } = require('./private-groups');
const { canModerateCountry } = require('./regional-moderation');
const LEASE_MS = 90000;
const millis = value => value?.toMillis?.() || 0;
const tokenValid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{16,100}$/.test(value);
function leaseData(actor, user, sessionId, now) {
  return {reviewerUid: actor.uid, reviewerUsername: user.username || '', sessionId,
    expiresAt: admin.firestore.Timestamp.fromMillis(now + LEASE_MS)};
}
async function countryReviewAction({actor, body}) {
  const countryCode = String(body.countryCode || '').trim().toUpperCase();
  const {sessionId, operation} = body;
  if (!/^[A-Z]{2}$/.test(countryCode) || !tokenValid(sessionId) ||
      !['acquire','renew','release'].includes(operation)) throw new Error('Invalid country review request');
  const ref = db.collection('country_review_locks').doc(countryCode);
  return db.runTransaction(async tx => {
    const [snapshot, userSnapshot] = await Promise.all([tx.get(ref), tx.get(db.collection('users').doc(actor.uid))]);
    const lock = snapshot.data() || {}, user = userSnapshot.data(), now = Date.now();
    const owns = lock.reviewerUid === actor.uid && lock.sessionId === sessionId;
    const alive = millis(lock.expiresAt) > now;
    if (operation === 'release') {if (owns) tx.delete(ref); return {released: owns};}
    if (!canModerateCountry(user, countryCode)) throw new Error('No permission to review this country');
    if (operation === 'acquire' && alive && !owns) return {acquired:false,reviewerUsername:lock.reviewerUsername || ''};
    if (operation === 'renew' && (!owns || !alive)) throw new Error('Country review lock expired');
    tx.set(ref, leaseData(actor, user, sessionId, now));
    return {[operation === 'acquire' ? 'acquired' : 'renewed']:true,leaseMillis:LEASE_MS};
  });
}
async function saveReviewCountries({actor, body}) {
  if (!Array.isArray(body.countryCodes) || body.countryCodes.length > 100) throw new Error('Invalid review countries');
  const codes = [...new Set(body.countryCodes.map(normalizeCountry))];
  if (codes.some(code => !code)) throw new Error('Invalid review countries');
  const ref = db.collection('users').doc(actor.uid);
  return db.runTransaction(async tx => {
    const [snapshot, config] = await Promise.all([tx.get(ref), tx.get(db.collection('app_config').doc('main'))]);
    const user = snapshot.data();
    if (user?.role !== 'admin' || !canModerateCountry(user,'LV')) throw new Error('No permission');
    const banned = (config.data()?.bannedCountryCodes || []).map(normalizeCountry);
    if (codes.some(code => banned.includes(code))) throw new Error('Country is not enabled');
    tx.update(ref, {adminSpotReviewCountryCodes:codes});
    return {countryCodes:codes};
  });
}
module.exports = {countryReviewAction, saveReviewCountries, leaseData, millis, tokenValid};
