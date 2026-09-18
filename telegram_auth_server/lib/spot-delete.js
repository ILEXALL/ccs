const { db } = require('./firebase-admin');

async function deleteSpotAction({actor, body}) {
  const spotId = typeof body.spotId === 'string' ? body.spotId.trim() : '';
  if (!spotId || spotId.includes('/')) throw new Error('Invalid spot ID');
  return db.runTransaction(async tx => {
    const spotRef = db.collection('spots').doc(spotId);
    const lockRef = db.collection('spot_review_locks').doc(spotId);
    const [userDoc, spotDoc, lockDoc] = await Promise.all([
      tx.get(db.collection('users').doc(actor.uid)), tx.get(spotRef), tx.get(lockRef),
    ]);
    const user = userDoc.data(), spot = spotDoc.data(), lock = lockDoc.data();
    if (!user || user.role !== 'admin' || user.deleted === true || user.banned === true) {
      throw new Error('Only admins can delete spots');
    }
    if (lock?.expiresAt?.toMillis() > Date.now() && lock.reviewerUid !== actor.uid) {
      throw new Error(`This spot is being reviewed by @${lock.reviewerUsername || 'another reviewer'}`);
    }
    if (!spot) return {deleted: true}; // A lost response can safely be retried.
    const groupIds = Array.isArray(spot.sharedGroupIds) ? [...new Set(spot.sharedGroupIds)] : [];
    if (groupIds.length > 8 || groupIds.some(id => typeof id !== 'string' || !id || id.includes('/'))) {
      throw new Error('Invalid stored spot audience');
    }
    tx.delete(spotRef);
    tx.delete(lockRef);
    tx.delete(db.collection('forum_topics').doc(`temporary_spot_${spotId}`));
    tx.delete(db.collection('forum_publications').doc(`temporary_spot_${spotId}`));
    for (const id of groupIds) {
      tx.delete(db.collection('chats').doc(id).collection('spot_links').doc(spotId));
    }
    return {deleted: true};
  });
}
module.exports = {deleteSpotAction};
