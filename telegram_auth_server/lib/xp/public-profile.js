const {db} = require('../firebase-admin');
const {createdSpotCount} = require('./spot-counts');
const {assertPublicXpAccess, catalog, retiredAchievementIds} = require('./achievements');
const {rewardCatalog, rewardProgress} = require('./rewards');
const {publicHistory} = require('./history');

// Public views never return raw ledger documents, moderation reasons or object IDs.
async function publicXpProfile(actorId, userId, section = 'stats', offset = 0) {
  await assertPublicXpAccess(actorId, userId);
  if (section === 'stats') {
    const stats = (await db.collection('xp_user_stats').doc(userId).get()).data() || {};
    return {xpTotal: Math.max(0, Number(stats.xpTotal) || 0)};
  }
  if (section === 'rewards') {
    const result = await rewardProgress(userId, {sync: false});
    return {weekly: {status: 'private', items: []}, items: result.items.map(({pending, ...item}) => ({...item, pending: 0}))};
  }
  if (section !== 'history') throw new Error('Unknown public XP section');
  const rewards = new Map(rewardCatalog().map(item => [item.id, item]));
  const achievements = new Set([...catalog().map(item => item.id), ...retiredAchievementIds]);
  const snapshot = await db.collection('xp_transactions').where('userId', '==', userId).get();
  return publicHistory(snapshot.docs.map(doc => doc.data()), rewards, achievements, offset);
}
async function creatorSpotCount(actorId, userId) {
  // Owners can inspect their own count even when their profile is private.
  if (actorId !== userId) await assertPublicXpAccess(actorId, userId);
  return {count: await createdSpotCount(userId)};
}
module.exports = {publicXpProfile, creatorSpotCount};
