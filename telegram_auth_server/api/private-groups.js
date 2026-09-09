const { admin, db } = require('../lib/firebase-admin');
const { ownerUid, directoryEntry, acceptedMemberFields, countryCode, profileCountry, directoryCountry } = require('../lib/private-groups');

// Legacy records have no historical country. Assign the owner's current country
// once, transactionally, so later profile changes never relocate the group.
async function ensureGroupCountry(chatRef) {
  return db.runTransaction(async tx => {
    const doc = await tx.get(chatRef);
    if (!doc.exists) return '';
    const chat = doc.data();
    if (chat.isGroup !== true) return '';
    if (countryCode(chat.countryCode)) return countryCode(chat.countryCode);
    let country = countryCode(chat.country);
    if (!country && ownerUid(chat)) {
      const owner = await tx.get(db.collection('users').doc(ownerUid(chat)));
      country = profileCountry(owner.data() || {});
    }
    if (country) tx.update(chatRef, { countryCode: country });
    return country;
  });
}

function fail(status, message) { throw Object.assign(new Error(message), { status }); }
function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 200 && !value.includes('/');
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  try {
    if (req.method !== 'POST') fail(405, 'Method not allowed.');
    const bearer = req.headers.authorization || '';
    if (!bearer.startsWith('Bearer ')) fail(401, 'Sign in first.');
    let token;
    try { token = await admin.auth().verifyIdToken(bearer.slice(7)); }
    catch { fail(401, 'Sign in again.'); }
    const uid = token.uid;
    const actorDoc = await db.collection('users').doc(uid).get();
    const actor = actorDoc.data();
    if (!actor || actor.deleted === true || actor.banned === true) fail(403, 'Account unavailable.');
    const canMonitor = ['admin', 'moderator'].includes(actor.role) || actor.globalChatModerator === true || actor.globalModerator === true;
    const { action, chatId, requesterUid, decision } = req.body || {};
    if (action === 'directory') {
      const selectedCountry = directoryCountry(actor, req.body.countryCode);
      if (!selectedCountry) fail(400, 'Set a valid country in your profile.');
      const snapshot = await db.collection('chats').where('isGroup', '==', true).get();
      const countries = await Promise.all(snapshot.docs.map(doc =>
        countryCode(doc.data().countryCode) || ensureGroupCountry(doc.ref)));
      const visible = snapshot.docs.filter((doc, i) => countries[i] === selectedCountry);
      const groups = visible.filter(doc => doc.data().isPrivate === true);
      const requests = groups.length ? await db.getAll(...groups.map(doc => doc.ref.collection('join_requests').doc(uid))) : [];
      return res.status(200).json({ countryCode: selectedCountry, visibleGroupIds: visible.map(doc => doc.id), groups: groups.map((doc, i) => directoryEntry(doc.id, doc.data(), uid, canMonitor, requests[i].data()?.status || '')) });
    }
    if (!validId(chatId)) fail(400, 'Invalid group.');
    const chatRef = db.collection('chats').doc(chatId);
    if (action === 'requests') {
      const chatDoc = await chatRef.get();
      if (!chatDoc.exists || chatDoc.data().isGroup !== true || ownerUid(chatDoc.data()) !== uid) fail(403, 'Only the owner can review requests.');
      const requests = await chatRef.collection('join_requests').where('status', '==', 'pending').get();
      return res.status(200).json({ requests: requests.docs.map(doc => ({ uid: doc.id, username: doc.data().username })) });
    }
    if (!['request', 'decide'].includes(action)) fail(400, 'Invalid action.');
    if (action === 'decide' && (!validId(requesterUid) || !['accepted', 'rejected'].includes(decision))) fail(400, 'Invalid decision.');
    const targetUid = action === 'request' ? uid : requesterUid;
    const requestRef = chatRef.collection('join_requests').doc(targetUid);
    if (action === 'request') await ensureGroupCountry(chatRef);
    const result = await db.runTransaction(async tx => {
      const [chatDoc, requestDoc, targetDoc] = await Promise.all([tx.get(chatRef), tx.get(requestRef), tx.get(db.collection('users').doc(targetUid))]);
      if (!chatDoc.exists || chatDoc.data().isGroup !== true) fail(404, 'Group no longer exists.');
      const chat = chatDoc.data();
      const owner = ownerUid(chat);
      const now = admin.firestore.FieldValue.serverTimestamp();
      if (action === 'request') {
        // Re-read the profile in the transaction, including country/role changes.
        const applicant = targetDoc.data() || {};
        if (applicant.deleted === true || applicant.banned === true) fail(403, 'Account unavailable.');
        if (applicant.role !== 'admin' && (!profileCountry(applicant) || profileCountry(applicant) !== countryCode(chat.countryCode))) fail(403, 'This group is outside your profile country.');
        if (chat.isPrivate !== true || (chat.memberIds || []).includes(uid)) fail(409, 'This group does not need a join request.');
        if (requestDoc.exists) return { status: requestDoc.data().status };
        tx.create(requestRef, { username: actor.username || 'driver', status: 'pending', createdAt: now });
        tx.create(db.collection('user_notifications').doc(`group_request_${chatId}_${uid}`), {
          userId: owner, type: 'group_join_request', chatId, actorUserId: uid,
          actorUsername: actor.username || 'driver', title: 'Group join request',
          body: `@${actor.username || 'driver'} wants to join ${chat.name || 'your group'}.`, read: false, createdAt: now,
        });
        return { status: 'pending' };
      }
      if (owner !== uid) fail(403, 'Only the owner can review requests.');
      if (!requestDoc.exists) fail(404, 'Request no longer exists.');
      if (requestDoc.data().status !== 'pending') return { status: requestDoc.data().status };
      if (decision === 'accepted') {
        const target = targetDoc.data();
        if (!target || target.banned === true || target.deleted === true) fail(409, 'Applicant account unavailable.');
        tx.update(chatRef, { ...acceptedMemberFields(chat, targetUid, target), updatedAt: now });
      }
      tx.update(requestRef, { status: decision, decidedBy: uid, decidedAt: now });
      tx.set(db.collection('user_notifications').doc(`group_decision_${chatId}_${targetUid}`), {
        userId: targetUid, type: 'group_join_decision', chatId, status: decision,
        title: 'Group join request', body: `Your request to join ${chat.name || 'the group'} was ${decision}.`,
        read: false, createdAt: now,
      });
      return { status: decision };
    });
    return res.status(200).json(result);
  } catch (error) {
    if (!error.status) console.error('Private groups:', error);
    return res.status(error.status || 500).json({ message: error.status ? error.message : 'Could not update group. Please retry.' });
  }
};
