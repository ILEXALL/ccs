const {assessLocation} = require('../lib/location-integrity');
const {awardXp} = require('../lib/xp/xp-firestore');
const {syncAchievements} = require('../lib/xp/achievements');
const {admin, db} = require('../lib/firebase-admin');
const {recordSpotVisit} = require('../lib/spot-visits');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ok: false}); }
  let token;
  try {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return res.status(401).json({ok: false});
    token = await admin.auth().verifyIdToken(header.slice(7));
  } catch (_) { return res.status(401).json({ok: false}); }
  try {
    const stored = req.body?.gpsFix ? null : (await db.collection('live_locations').doc(token.uid).get()).data();
    const fix = req.body?.gpsFix || (stored && {latitude: stored.lat, longitude: stored.lng,
      accuracy: stored.accuracy, isMocked: stored.isMocked,
      recordedAtMillis: stored.recordedAtMillis ?? stored.updatedAt?.toMillis?.()});
    if (!await assessLocation(token.uid, fix)) throw new Error('Location could not be verified');
    const result = await recordSpotVisit(db, token.uid, req.body?.spotId, Date.now(), req.body?.gpsFix ?? null);
    if (result.event) {
      result.xp = await awardXp({userId: token.uid, action: 'event.attended', objectType: 'event',
        objectId: req.body.spotId, stage: 'attended', amount: 200,
        metadata: {reason: 'Event attended'}});
    }
    await syncAchievements(token.uid);
    return res.status(200).json({ok: true, result});
  } catch (_) { return res.status(403).json({ok: false, error: 'Visit could not be recorded'}); }
};
