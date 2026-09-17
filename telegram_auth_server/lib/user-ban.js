const { admin, db } = require('./firebase-admin');
const { canModerateCountry } = require('./regional-moderation');
const { countryCode } = require('./private-groups');
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
    const [actorDoc, targetDoc, logDoc, admins] = await Promise.all([
      tx.get(actorRef), tx.get(targetRef), tx.get(logRef),
      tx.get(db.collection('users').where('role', '==', 'admin')),
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

module.exports = { banUserAction };
