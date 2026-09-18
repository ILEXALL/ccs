const {db} = require('../firebase-admin');
const {assertPublicXpAccess, catalog, retiredAchievementIds} = require('./achievements');
const {rewardCatalog, rewardProgress} = require('./rewards');

// Public views never return raw ledger documents, moderation reasons or object IDs.
async function publicXpProfile(actorId, userId, section = 'stats') {
  await assertPublicXpAccess(actorId, userId);
  if (section === 'stats') {
    const stats = (await db.collection('xp_user_stats').doc(userId).get()).data() || {};
    return {xpTotal: Math.max(0, Number(stats.xpTotal) || 0)};
  }
  if (section === 'rewards') {
    const result = await rewardProgress(userId);
    return {weekly: result.weekly, items: result.items.map(({pending, ...item}) => ({...item, pending: 0}))};
  }
  if (section !== 'history') throw new Error('Unknown public XP section');
  const rewards = new Map(rewardCatalog().map(item => [item.id, item]));
  const achievements = new Set([...catalog().map(item => item.id), ...retiredAchievementIds]);
  const snapshot = await db.collection('xp_transactions').where('userId', '==', userId).get();
  const items = snapshot.docs.map(doc => doc.data()).filter(row =>
    row.status === 'confirmed' && row.amount > 0 && !row.adjustmentOf &&
    (rewards.has(row.action) || (row.action === 'achievement.unlock' && achievements.has(row.objectId))))
    .map(row => ({
      action: row.action,
      objectType: row.action === 'achievement.unlock' ? 'achievement' :
        rewards.get(row.action).category,
      achievementId: row.action === 'achievement.unlock' ? row.objectId : '',
      amount: row.amount,
      createdAtMillis: row.createdAt?.toMillis?.() || Number(row.createdAtMillis) || 0,
    })).sort((a, b) => b.createdAtMillis - a.createdAtMillis).slice(0, 100);
  return {items};
}
module.exports = {publicXpProfile};
