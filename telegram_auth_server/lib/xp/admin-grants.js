const crypto = require('node:crypto');
const {admin, db} = require('../firebase-admin');
const {calculateLevel, XP_RULES_VERSION} = require('./xp-engine');

function reject(message) { const error = new Error(message); error.grantRejected = true; throw error; }
async function requireAdmin(tx, actorId) {
  const actor = (await tx.get(db.collection('users').doc(actorId))).data();
  if (!actor || actor.role !== 'admin' || actor.deleted || actor.banned) throw new Error('Admin access required');
}
async function grantTarget(actorId, input) {
  const key = String(input.username || '').trim().replace(/^@/, '').toLowerCase();
  if (!/^[a-z0-9_]{3,30}$/.test(key)) reject('Enter a valid username');
  return db.runTransaction(async tx => {
    await requireAdmin(tx, actorId);
    const mapping = (await tx.get(db.collection('usernames').doc(key))).data();
    if (!mapping?.uid || typeof mapping.uid !== 'string' || mapping.uid.includes('/')) reject('Username not found');
    const user = (await tx.get(db.collection('users').doc(mapping.uid))).data();
    if (!user || String(user.username || '').toLowerCase() !== key) reject('Username changed; verify the recipient');
    if (mapping.uid === actorId) reject('Cannot grant XP to yourself');
    if (user.deleted || user.banned || user.xpBlocked) reject('Recipient is blocked or being deleted');
    return {userId: mapping.uid, username: user.username};
  });
}

// Only explicit pre-write validation failures are safe to let the client edit.
// Unknown/transport failures must keep the same persisted request ID for retry.
async function grantRequest(operation, actorId, input) {
  try { return await operation(actorId, input); }
  catch (error) {
    if (error.grantRejected) return {rejected: true, message: error.message};
    throw error;
  }
}

// Explicit administrative adjustments are outside the weekly earning allowance.
// Reuse the historical ledger convention so revoke/restore remains supported.
async function grantXp(actorId, input) {
  const username = typeof input.username === 'string' ? input.username.trim().replace(/^@/, '') : '';
  const {amount, requestId, userId} = input;
  const reason = typeof input.reason === 'string' ? input.reason.trim() : '';
  if (!/^[a-zA-Z0-9_]{3,30}$/.test(username) ||
      !Number.isSafeInteger(amount) || amount < 1 || amount > 3000 ||
      typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{8,128}$/.test(requestId) || !reason || reason.length > 500) {
    reject('Provide a username, 1–3000 XP, a reason and a valid request ID');
  }
  if (typeof userId !== 'string' || !userId || userId.includes('/')) reject('Verify the recipient first');
  const usernameKey = username.toLowerCase();
  const id = crypto.createHash('sha256').update(JSON.stringify(['grant', actorId, requestId])).digest('hex');
  const auditRef = db.collection('xp_admin_audit').doc(id);
  const ledgerRef = db.collection('xp_transactions').doc(`grant_${id}`);
  return db.runTransaction(async tx => {
    await requireAdmin(tx, actorId);
    const previous = await tx.get(auditRef);
    if (previous.exists) {
      const old = previous.data();
      if (old.userId !== userId || old.usernameKey !== usernameKey || old.amount !== amount || old.reason !== reason) {
        throw new Error('Request ID already used for another grant');
      }
      return {...old.result, duplicate: true};
    }
    const mapping = (await tx.get(db.collection('usernames').doc(usernameKey))).data();
    const uid = mapping?.uid;
    if (uid !== userId) reject('Username changed; verify the recipient');
    if (uid === actorId) reject('Cannot grant XP to yourself');
    const user = (await tx.get(db.collection('users').doc(uid))).data();
    if (!user || String(user.username || '').toLowerCase() !== usernameKey) {
      reject('Username changed; verify the recipient');
    }
    const deletion = await tx.get(db.collection('account_deletions').doc(uid));
    if (user.deleted || user.banned || user.xpBlocked || deletion.exists) {
      reject('Recipient is blocked or being deleted');
    }
    const statsRef = db.collection('xp_user_stats').doc(uid);
    const statsSnapshot = await tx.get(statsRef);
    const stats = statsSnapshot.data() || {};
    const before = statsSnapshot.exists ? stats.xpTotal : (user.xpTotal ?? 0);
    const total = before + amount;
    if (!Number.isSafeInteger(before) || before < 0 || !Number.isSafeInteger(total)) {
      reject('Inconsistent XP balance');
    }
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const result = {userId: uid, username: user.username, amount, before,
      xpTotal: total, level: calculateLevel(total), transactionId: ledgerRef.id || `grant_${id}`, duplicate: false};
    tx.create(ledgerRef, {transactionId: result.transactionId, userId: uid,
      action: 'admin.grant', objectType: 'admin_reward', objectId: requestId,
      stage: 'granted', amount, requestedAmount: amount, status: 'confirmed',
      actorId, reason, metadata: {reason}, rulesVersion: XP_RULES_VERSION,
      historicalCatchup: true, weekKey: null, createdAt: timestamp, confirmedAt: timestamp});
    tx.set(statsRef, {userId: uid, xpTotal: total, level: result.level,
      xpUpdatedAt: timestamp, xpLastTransactionId: result.transactionId,
      ...(!statsSnapshot.exists ? {createdAt: timestamp} : {})}, {merge: true});
    tx.create(auditRef, {actorId, userId: uid, usernameKey, amount, reason,
      operation: 'grant', transactionId: result.transactionId,
      before, after: total, createdAt: timestamp, result});
    return result;
  });
}

module.exports = {grantXp, grantTarget, grantRequest};
