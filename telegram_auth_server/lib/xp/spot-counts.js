const {db} = require('../firebase-admin');

// Only approved permanent creations count toward profile totals and milestones.
// Prefer the original creator; ownerUid supports older records only.
function qualifiesCreatedSpot(spot, userId) {
  return (spot.addedByUid || spot.ownerUid) === userId &&
    spot.status === 'approved' && spot.isTemporary !== true && spot.deleted !== true;
}

async function createdSpotCount(userId) {
  if (typeof userId !== 'string' || !userId || userId.includes('/')) throw new Error('Invalid user');
  const snapshots = await Promise.all([
    db.collection('spots').where('addedByUid', '==', userId).get(),
    db.collection('spots').where('ownerUid', '==', userId).get(),
  ]);
  const ids = new Set();
  for (const snapshot of snapshots) for (const doc of snapshot.docs) {
    if (qualifiesCreatedSpot(doc.data(), userId)) ids.add(doc.id);
  }
  return ids.size;
}
module.exports = {createdSpotCount, qualifiesCreatedSpot};
