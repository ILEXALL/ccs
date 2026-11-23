const crypto = require('node:crypto');
const DAY = 86400000;
const millis = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);

function inactivityWarning(topic, now) {
  if (!topic || topic.deleted === true || (topic.status || 'approved') !== 'approved' ||
      typeof topic.authorId !== 'string' || !topic.authorId || topic.authorId.includes('/')) return null;
  const activity = Math.max(millis(topic.createdAt), millis(topic.lastReplyAt));
  const hidesAt = activity + 30 * DAY;
  const expires = millis(topic.autoExpiresAt ?? topic.temporarySpotExpiresAt);
  if (!Number.isFinite(activity) || activity <= 0 || now < hidesAt - DAY || now >= hidesAt ||
      (expires > 0 && expires <= hidesAt)) return null;
  return {activity, hidesAt, authorId: topic.authorId};
}

// Bounded, resumable scan uses document IDs, so legacy topics with no lastReplyAt
// are covered without a new composite index. Delivery keys include activity.
async function dispatchForumInactivity({db, send, now = Date.now(), budgetMs = 10000}) {
  const ref = db.collection('forum_inactivity_jobs').doc('scheduler');
  const token = crypto.randomUUID();
  const state = await db.runTransaction(async tx => {
    const current = (await tx.get(ref)).data() || {};
    if (current.leaseUntil > now) return null;
    tx.set(ref, {token, leaseUntil: now + 120000}, {merge: true});
    return current;
  });
  if (!state) return {busy: true, scanned: 0, processed: 0};
  let cursor = state.cursor || '', scanned = 0, processed = 0;
  const deadline = Date.now() + budgetMs;
  try {
    while (scanned < 200 && Date.now() < deadline) {
      let query = db.collection('forum_topics').orderBy('__name__').limit(25);
      if (cursor) query = query.startAfter(cursor);
      const page = (await query.get()).docs;
      for (const doc of page) {
        if (Date.now() >= deadline) break;
        const topic = (await db.collection('forum_topics').doc(doc.id).get()).data();
        const warning = inactivityWarning(topic, now);
        if (warning) {
          const key = `forum_inactivity:${doc.id}:${warning.activity}`;
          const hours = Math.max(1, Math.ceil((warning.hidesAt - now) / 3600000));
          await send({userId: warning.authorId, settingName: 'commentNotifications',
            deliveryKey: key,
            notificationId: 'forum_inactivity_' + crypto.createHash('sha256').update(key).digest('hex'),
            title: 'Your forum topic will be hidden soon',
            body: `“${String(topic.title || 'Forum topic')}” will be hidden in ${hours} ${hours === 1 ? 'hour' : 'hours'} due to inactivity. Add a reply to keep it active.`,
            data: {type: 'forum_inactivity_warning', topicId: doc.id,
              topicTitle: String(topic.title || 'Forum topic'),
              activityAt: warning.activity, hidesAt: warning.hidesAt}});
          processed++;
        }
        cursor = doc.id;
        scanned++;
      }
      if (page.length < 25 && (page.length === 0 || cursor === page.at(-1).id)) {
        cursor = '';
        break;
      }
    }
    return {scanned, processed};
  } finally {
    await db.runTransaction(async tx => {
      if ((await tx.get(ref)).data()?.token === token) {
        tx.set(ref, {cursor, leaseUntil: 0, lastRunAt: now}, {merge: true});
      }
    });
  }
}
module.exports = {inactivityWarning, dispatchForumInactivity};
