const {randomUUID} = require('node:crypto');
const {db} = require('./firebase-admin');

// A failed dispatch remains durable. Subsequent review requests and notification
// center requests retry it; delivery keys in sendPushToUser suppress duplicates.
async function drainForumPublications(dispatch) {
  const pending = await db.collection('forum_publications').limit(5).get();
  for (const job of pending.docs) {
    const token = randomUUID();
    const claimed = await db.runTransaction(async tx => {
      const current = await tx.get(job.ref);
      if (!current.exists || current.data().leaseUntilMillis > Date.now()) return false;
      tx.update(job.ref, {leaseToken: token, leaseUntilMillis: Date.now() + 300000});
      return true;
    });
    if (!claimed) continue;
    const finish = async success => db.runTransaction(async tx => {
      const current = await tx.get(job.ref);
      if (!current.exists || current.data().leaseToken !== token) return;
      if (success) tx.delete(job.ref);
      else tx.update(job.ref, {leaseToken: '', leaseUntilMillis: 0});
    });
    try {
      const topic = (await db.collection('forum_topics').doc(job.id).get()).data();
      if (topic?.status === 'approved' && topic.visibility !== 'group') {
        await dispatch(topic.authorId, {topicId: job.id});
      }
      await finish(true);
    } catch (error) {
      await finish(false).catch(() => {});
      console.error('Forum publication deferred:', job.id, error.message);
    }
  }
}
module.exports = {drainForumPublications};
