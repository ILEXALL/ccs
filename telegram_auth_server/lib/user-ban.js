const { admin, db } = require('./firebase-admin');
const { canModerateCountry } = require('./regional-moderation');
const { countryCode } = require('./private-groups');
const { millis, activeBan, banHistory } = require('./ban-history');
const profileCountry = user => countryCode(user.country);

const text = value => typeof value === 'string' ? value.trim() : '';
const validId = value => /^[A-Za-z0-9_-]{1,128}$/.test(value);

async function banUserAction({ actor, body }) {
  const targetUid = text(body.targetUserId);
  const requestId = text(body.requestId);
  const reason = text(body.reason);
  const days = body.days;
  if (!validId(targetUid) || !validId(requestId) || !reason || reason.length > 1000 ||
      !Number.isInteger(days) || days < 1 || days > 3650) throw new Error('Invalid ban request');
  const actorRef = db.collection('users').doc(actor.uid);
  const targetRef = db.collection('users').doc(targetUid);
  const logRef = db.collection('moderation_logs').doc(`ban_${actor.uid}_${requestId}`);

  return db.runTransaction(async tx => {
    const [actorDoc, targetDoc, logDoc, admins, history] = await Promise.all([
      tx.get(actorRef), tx.get(targetRef), tx.get(logRef),
      tx.get(db.collection('users').where('role', '==', 'admin')),
      tx.get(db.collection('moderation_logs').where('targetUserId', '==', targetUid)),
    ]);
    const moderator = actorDoc.data();
    const target = targetDoc.data();
    // Read authoritative profiles on every attempt, including transaction retries.
    if (!actorDoc.exists || !targetDoc.exists || target.deleted === true ||
        targetUid === actor.uid || target.role === 'admin' ||
        (moderator.role !== 'admin' && target.role !== 'user') ||
        !canModerateCountry(moderator, profileCountry(target))) {
      throw new Error('No permission to ban this user in their profile country');
    }
    if (logDoc.exists) return { alreadyApplied: true };
    preserveLegacyBan(tx, targetUid, target, history.docs.map(d => d.data()));
    const now = Date.now();
    const until = admin.firestore.Timestamp.fromMillis(now + days * 86400000);
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const devices = [...new Set([...(Array.isArray(target.deviceIds) ? target.deviceIds : []),
      target.lastDeviceId].map(text).filter(id => validId(id) && id.length >= 8))].slice(0, 100);
    tx.update(targetRef, {
      banned: true, bannedUntil: until, banReason: reason,
      bannedByUid: actor.uid, bannedBy: text(moderator.username), bannedAt: timestamp,
      knownDeviceIdsAtBan: devices, updatedAt: timestamp,
    });
    for (const deviceId of devices) tx.set(db.collection('device_bans').doc(deviceId), {
      deviceId, userId: targetUid, username: text(target.username),
      sourceUserUid: targetUid, sourceUsername: text(target.username),
      banned: true, bannedUntil: until, reason, bannedByUid: actor.uid,
      bannedBy: text(moderator.username), bannedAt: timestamp, updatedAt: timestamp,
    });
    const countryCode = profileCountry(target);
    tx.create(logRef, { action: 'user_banned', actorUid: actor.uid,
      actorUsername: text(moderator.username),
      targetUserId: targetUid, countryCode, reason, days, bannedUntil: until, createdAt: timestamp });
    if (moderator.role === 'moderator') {
      for (const doc of admins.docs) {
        const user = doc.data();
        if (user.deleted === true || user.banned === true) continue;
        tx.create(db.collection('admin_notifications').doc(`${logRef.id}_${doc.id}`), {
          userId: doc.id, type: 'moderator_user_banned',
          title: 'Moderator banned a user',
          body: `@${text(moderator.username)} banned @${text(target.username)} (${countryCode}) for ${days} days. Reason: ${reason}`,
          actorUserId: actor.uid, actorUsername: text(moderator.username),
          reportedUid: targetUid, reportedUsername: text(target.username),
          countryCode, reason, days, bannedUntil: until,
          moderationLogId: logRef.id, read: false, createdAt: timestamp, createdAtMillis: now,
        });
      }
    }
    return { alreadyApplied: false };
  });
}

function preserveLegacyBan(tx, uid, user, logs) {
  const at = millis(user.bannedAt);
  const lifted = millis(user.unbannedAt);
  if (at !== null && user.banned === false && lifted !== null && lifted >= at) {
    tx.set(db.collection('moderation_logs').doc(`legacy_unban_${uid}_${at}`), {
      action: 'user_unbanned', targetUserId: uid, countryCode: profileCountry(user),
      banStartedAt: user.bannedAt, createdAt: user.unbannedAt, legacy: true,
    });
  }
  if (at === null || logs.some(l => l.action === 'user_banned' &&
      (millis(l.createdAt) === at || (millis(user.bannedUntil) !== null &&
        millis(l.bannedUntil) === millis(user.bannedUntil))))) return;
  tx.set(db.collection('moderation_logs').doc(`legacy_ban_${uid}_${at}`), {
    action: 'user_banned', targetUserId: uid, countryCode: profileCountry(user),
    actorUid: text(user.bannedByUid), actorUsername: text(user.bannedBy),
    createdAt: user.bannedAt, bannedUntil: user.bannedUntil || null,
    liftedAt: user.banned === false ? user.unbannedAt || null : null,
    reason: user.banReason || '', legacy: true,
  });
}

async function unbanUserAction({ actor, body }) {
  const uid = text(body.targetUserId);
  if (!validId(uid)) throw new Error('Invalid user');
  return db.runTransaction(async tx => {
    const ref = db.collection('users').doc(uid);
    const [actorDoc, targetDoc, history] = await Promise.all([
      tx.get(db.collection('users').doc(actor.uid)), tx.get(ref),
      tx.get(db.collection('moderation_logs').where('targetUserId', '==', uid)),
    ]);
    const moderator = actorDoc.data(), user = targetDoc.data();
    if (!user || uid === actor.uid || user.role === 'admin' ||
        (moderator?.role !== 'admin' && user.role !== 'user') ||
        !canModerateCountry(moderator, profileCountry(user))) throw new Error('No permission to unban this user');
    const devices = [...new Set([...(user.deviceIds || []), ...(user.knownDeviceIdsAtBan || []),
      user.lastDeviceId].map(text).filter(validId))].slice(0, 100);
    const deviceDocs = await Promise.all(devices.map(id => tx.get(db.collection('device_bans').doc(id))));
    if (user.banned !== true) return { alreadyApplied: true };
    preserveLegacyBan(tx, uid, user, history.docs.map(d => d.data()));
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const update = { banned: false, unbannedAt: timestamp, unbannedByUid: actor.uid,
      unbannedBy: text(moderator.username), updatedAt: timestamp };
    // Retain the original dates and reason as a legacy history fallback.
    tx.update(ref, update);
    for (const doc of deviceDocs) {
      if (doc.exists && (doc.data().sourceUserUid || doc.data().userId) === uid) tx.update(doc.ref, update);
    }
    tx.create(db.collection('moderation_logs').doc(), { action: 'user_unbanned',
      targetUserId: uid, actorUid: actor.uid, countryCode: profileCountry(user),
      banStartedAt: user.bannedAt || null, createdAt: timestamp });
    return { alreadyApplied: false };
  });
}

async function listBansAction({ actor, body }) {
  if (!['admin', 'moderator'].includes(actor.user.role)) throw new Error('Staff access required');
  let query = db.collection('users').orderBy('bannedAt', 'desc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'desc').limit(50);
  if (body.cursor) {
    if (!validId(body.cursor)) throw new Error('Invalid cursor');
    const cursor = await db.collection('users').doc(body.cursor).get();
    if (!cursor.exists || !cursor.data().bannedAt) throw new Error('Invalid cursor');
    query = query.startAfter(cursor);
  }
  const page = await query.get();
  const now = Date.now();
  const entries = [];
  const actorNames = new Map();
  for (const doc of page.docs) {
    const user = doc.data();
    if (!canModerateCountry(actor.user, profileCountry(user))) continue;
    const logs = await db.collection('moderation_logs').where('targetUserId', '==', doc.id).get();
    const history = banHistory(user, logs.docs.map(d => d.data()));
    for (const ban of history) {
      if (ban.bannedBy || !validId(ban.bannedByUid)) continue;
      if (!actorNames.has(ban.bannedByUid)) {
        const moderator = await db.collection('users').doc(ban.bannedByUid).get();
        actorNames.set(ban.bannedByUid, text(moderator.data()?.username));
      }
      ban.bannedBy = actorNames.get(ban.bannedByUid);
    }
    if (!history.length && !user.banned) continue;
    entries.push({ uid: doc.id, username: text(user.username), country: profileCountry(user),
      canUnban: doc.id !== actor.uid && user.role !== 'admin' &&
        (actor.user.role === 'admin' || user.role === 'user'),
      active: activeBan(user, now), expiresAt: millis(user.bannedUntil), history });
  }
  return { entries, cursor: page.size === 50 ? page.docs[page.docs.length - 1].id : null };
}

module.exports = { banUserAction, unbanUserAction, listBansAction };
