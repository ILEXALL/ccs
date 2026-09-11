const { admin, db } = require('./firebase-admin');
const { canModerateCountry, communityCountry } = require('./regional-moderation');
const text = v => typeof v === 'string' ? v.trim() : '';
const millis = v => v && typeof v.toMillis === 'function' ? v.toMillis() : 0;
const LEASE_MS = 90000;
const activeStaff = u => u && !u.deleted && !u.banned && ['admin', 'moderator'].includes(u.role);
const topicView = doc => {
  const d = doc.data();
  return {id: doc.id, title: text(d.title), description: text(d.description),
    authorName: text(d.authorName), categoryId: text(d.categoryId), category: text(d.category),
    countryCode: communityCountry(d), createdAtMillis: millis(d.createdAt)};
};

async function forumReviewAction({ actor, body }) {
  const sessionId = text(body.sessionId);
  const operation = text(body.operation);
  if (body.countryCode !== undefined) throw new Error('Update the app to use automatic forum review access');
  if (!/^[A-Za-z0-9_-]{16,100}$/.test(sessionId) ||
      !['acquire','renew','release','decide'].includes(operation)) throw new Error('Invalid forum review request');
  const registry = db.collection('forum_review_locks').doc('sessions');
  return db.runTransaction(async tx => {
    const registryDoc = await tx.get(registry);
    const now = Date.now();
    let sessions = (registryDoc.data()?.sessions || []).filter(s => s.expiresAtMillis > now);
    const own = sessions.find(s => s.sessionId === sessionId && s.reviewerUid === actor.uid);
    if (operation === 'release') {
      if (own) tx.set(registry, {sessions: sessions.filter(s => s !== own)});
      return {released: !!own};
    }
    const ids = [...new Set([actor.uid, ...sessions.map(s => s.reviewerUid)])];
    const users = await Promise.all(ids.map(uid => tx.get(db.collection('users').doc(uid))));
    const profiles = new Map(users.map(d => [d.id, d.data()]));
    const user = profiles.get(actor.uid);
    if (!activeStaff(user)) throw new Error('No permission to review forum topics');
    if (!own && operation !== 'acquire') throw new Error('Review session expired. Reopen forum review.');
    // Use the current pending topics and assignments on every entry, heartbeat
    // and decision. No client-provided topic IDs or country lists grant access.
    const pending = await tx.get(db.collection('forum_topics').where('status', '==', 'pending'));
    const docs = pending.docs.filter(d => d.data().source !== 'temporary_spot');
    const eligibleByUid = new Map(ids.map(uid => [uid, new Set(docs.filter(d => canModerateCountry(profiles.get(uid), communityCountry(d.data()))).map(d => d.id))]));
    const eligible = uid => eligibleByUid.get(uid);
    sessions = sessions.filter(s => activeStaff(profiles.get(s.reviewerUid)));
    const candidate = own || {sessionId, reviewerUid: actor.uid, startedAtMillis: Math.max(now, ...sessions.map(s => s.startedAtMillis + 1)), expiresAtMillis: now + LEASE_MS};
    if (!own) sessions.push(candidate);
    sessions.sort((a,b) => a.startedAtMillis - b.startedAtMillis || a.sessionId.localeCompare(b.sessionId));
    const accepted = [];
    let blocker;
    for (const session of sessions) {
      const topics = eligible(session.reviewerUid);
      const conflict = accepted.find(other => [...topics].some(id => other.topics.has(id)));
      if (session === candidate && conflict) blocker = conflict.session;
      if (!conflict) accepted.push({session, topics});
    }
    if (blocker) {
      tx.set(registry, {sessions: sessions.filter(s => s !== candidate || !!own)});
      return {blocked: true, acquired: false, renewed: false,
        reviewerUsername: text(profiles.get(blocker.reviewerUid)?.username)};
    }
    if (sessions.length > 100) throw new Error('Too many review sessions. Please try again shortly.');
    candidate.expiresAtMillis = now + LEASE_MS;
    const saveRegistry = () => tx.set(registry, {sessions});
    const topics = docs.filter(d => eligible(actor.uid).has(d.id)).map(topicView)
      .sort((a,b) => a.createdAtMillis-b.createdAtMillis || a.id.localeCompare(b.id));
    if (operation === 'acquire' || operation === 'renew') {
      saveRegistry();
      return {acquired: operation === 'acquire', renewed: operation === 'renew', topics};
    }
    const topicId = text(body.topicId), status = text(body.status);
    const reason = status === 'rejected' ? text(body.rejectionReason) : '';
    if (!topicId || topicId.includes('/') || !['approved','rejected'].includes(status) ||
        (status === 'rejected' && (!reason || reason.length > 2000))) throw new Error('Invalid review decision');
    const ref = db.collection('forum_topics').doc(topicId);
    const doc = await tx.get(ref), topic = doc.data();
    if (!topic || !canModerateCountry(user, communityCountry(topic))) throw new Error('Topic is outside your assigned countries');
    if (topic.source === 'temporary_spot') throw new Error('Review this event through spot review');
    if (topic.status !== 'pending') {
      if (topic.reviewSessionId === sessionId && topic.reviewedBy === actor.uid && topic.status === status) {
        saveRegistry(); return {alreadyDecided: true};
      }
      throw new Error('Topic is no longer pending review');
    }
    saveRegistry();
    tx.update(ref, {status, rejectionReason: reason || null, reviewedBy: actor.uid,
      reviewSessionId: sessionId, reviewedAt: admin.firestore.FieldValue.serverTimestamp()});
    if (text(topic.authorId)) tx.set(db.collection('user_notifications').doc(`forum_reviewed_${topicId}`), {
      userId: topic.authorId, type:'forum_reviewed', topicId, actorUserId:actor.uid, status,
      title: status === 'approved' ? 'Forum topic approved' : 'Forum topic rejected',
      body: status === 'approved' ? `Your topic "${text(topic.title)}" was approved.` : `Your topic "${text(topic.title)}" was rejected: ${reason}`,
      topicTitle:text(topic.title), rejectionReason:reason || null, read:false,
      createdAt:admin.firestore.FieldValue.serverTimestamp(),
    });
    return {alreadyDecided:false};
  });
}
module.exports={forumReviewAction};
