const {db} = require('../firebase-admin');

// Only approved permanent creations count toward profile totals and milestones.
// Prefer the original creator; ownerUid supports older records only.
function qualifiesCreatedSpot(spot, userId) {
  return (spot.addedByUid || spot.ownerUid) === userId &&
    spot.status === 'approved' && spot.isTemporary !== true && spot.deleted !== true;
}

async function createdSpotProgress(userId) {
  if (typeof userId !== 'string' || !userId || userId.includes('/')) throw new Error('Invalid user');
  const snapshots = await Promise.all([
    db.collection('spots').where('addedByUid', '==', userId).get(),
    db.collection('spots').where('ownerUid', '==', userId).get(),
  ]);
  const ids = new Set();
  const events = new Set();
  for (const snapshot of snapshots) for (const doc of snapshot.docs) {
    const spot = doc.data();
    if (qualifiesCreatedSpot(spot, userId)) ids.add(doc.id);
    if ((spot.addedByUid || spot.ownerUid) === userId && spot.status === 'approved' &&
        spot.isTemporary === true && spot.deleted !== true) events.add(doc.id);
  }
  return {spots: ids.size, meets: events.size};
}
async function createdSpotCount(userId) { return (await createdSpotProgress(userId)).spots; }
module.exports = {createdSpotCount, createdSpotProgress, qualifiesCreatedSpot};
