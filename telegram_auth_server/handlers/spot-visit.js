const {syncWeeklyTasks, syncAdminRewardClaims} = require('../lib/xp/weekly-tasks');
const {assessLocation} = require('../lib/location-integrity');
const {syncAchievements} = require('../lib/xp/achievements');
const {admin, db} = require('../lib/firebase-admin');
const {recordSpotVisit} = require('../lib/spot-visits');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ok: false}); }
  let token;
  try {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return res.status(401).json({ok: false});
    token = await admin.auth().verifyIdToken(header.slice(7), true);
  } catch (_) { return res.status(401).json({ok: false}); }
  try {
    const stored = req.body?.gpsFix ? null : (await db.collection('live_locations').doc(token.uid).get()).data();
    const fix = req.body?.gpsFix || (stored && {latitude: stored.lat, longitude: stored.lng,
      accuracy: stored.accuracy, isMocked: stored.isMocked,
      recordedAtMillis: stored.recordedAtMillis ?? stored.updatedAt?.toMillis?.()});
    if (!await assessLocation(token.uid, fix)) {
      await db.runTransaction(async tx => tx.delete(db.collection('spot_visit_sessions').doc(token.uid)));
      throw new Error('Location could not be verified');
    }
    const result = await recordSpotVisit(db, token.uid, req.body?.spotId, Date.now(), req.body?.gpsFix ?? null);
    if (result.recorded || result.rewardClaimed) await syncAdminRewardClaims(token.uid);
    if (!result.recorded) return res.status(200).json({ok: true, result});
    await syncWeeklyTasks(token.uid);
    await syncAchievements(token.uid);
    return res.status(200).json({ok: true, result});
  } catch (_) { return res.status(403).json({ok: false, error: 'Visit could not be recorded'}); }
};
