const crypto = require('node:crypto');
const {weekKeyFor} = require('./xp-engine');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
// Called inside the same transaction as the validated GPS visit. Reads precede all writes.
async function prepareTaskVisit(db, tx, userId, spotId, spot, now, dayKey, firstVisit, candidates) {
  const key = weekKeyFor(new Date(now));
  const ref = db.collection('weekly_visit_records').doc(hash(`${userId}|${spotId}|${dayKey}`));
  const existing = await tx.get(ref);
  const claims = [];
  for (const candidate of candidates) {
    const rewardRef = db.collection('admin_rewards').doc(candidate.id);
    const c = (await tx.get(rewardRef)).data();
    if (!c || !c.enabled || c.spotId !== spotId || now < Math.max(c.startsAt, c.createdAt) || now >= c.endsAt) continue;
    const claimRef = db.collection('admin_reward_claims').doc(hash(`${userId}|${candidate.id}`));
    if (!(await tx.get(claimRef)).exists) claims.push({ref: claimRef, data: {userId, rewardId: candidate.id, xp: c.xp, title: c.title, completedAt: now}});
  }
  return () => {
    if (!existing.exists) tx.create(ref, {userId, spotId, weekKey: key, dayKey, firstVisit,
      event: spot.isTemporary === true, ownerId: spot.addedByUid || spot.ownerUid || '',
      categories: Array.isArray(spot.categories) ? spot.categories.filter(c => typeof c === 'string') : [], recordedAtMillis: now});
    for (const c of claims) tx.create(c.ref, c.data);
  };
}
module.exports = {prepareTaskVisit};
