// Expose every confirmed award, but never private reasons, actors or target IDs.
function publicHistory(rows, rewards, achievements, offset = 0) {
  const start = Number.isSafeInteger(offset) && offset >= 0 ? offset : 0;
  const types = new Set(['profile','garage_car','spot','event','achievement','weekly_task','weekly_visit','admin_reward']);
  const items = rows.filter(row => row.status === 'confirmed' && Number.isFinite(row.amount) && row.amount > 0)
    .map(row => ({
      action: row.action,
      objectType: row.action === 'achievement.unlock' ? 'achievement' :
        rewards.get(row.action)?.category || (types.has(row.objectType) ? row.objectType : 'reward'),
      achievementId: row.action === 'achievement.unlock' && achievements.has(row.objectId) ? row.objectId : '',
      amount: row.amount,
      createdAtMillis: row.createdAt?.toMillis?.() || Number(row.createdAtMillis) || 0,
    })).sort((a,b) => b.createdAtMillis-a.createdAtMillis);
  return {items:items.slice(start,start+100),nextOffset:start+100<items.length?start+100:null};
}
module.exports={publicHistory};
