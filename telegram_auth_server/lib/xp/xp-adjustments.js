const crypto = require('node:crypto');
const { admin, db } = require('../firebase-admin');
const { calculateLevel } = require('./xp-engine');

async function adjustXp(actorId, input) {
  const { transactionId, requestId, reason, operation, expectedRevision } = input;
  for (const value of [actorId, transactionId, requestId, reason]) {
    if (typeof value !== 'string' || !value.trim() || value.length > 1000) {
      throw new Error('Missing or invalid adjustment details');
    }
  }
  if (transactionId.includes('/') || !['revoke', 'restore'].includes(operation) ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new Error('Invalid XP adjustment');
  }
  const id = crypto.createHash('sha256').update(JSON.stringify([actorId, requestId])).digest('hex');
  const auditRef = db.collection('xp_admin_audit').doc(id);
  const sourceRef = db.collection('xp_transactions').doc(transactionId);
  return db.runTransaction(async (tx) => {
    // Recheck authority inside the same transaction as the balance change.
    const actorSnapshot = await tx.get(db.collection('users').doc(actorId));
    const actor = actorSnapshot.data() || {};
    if (!actorSnapshot.exists || actor.banned || actor.deleted || actor.role !== 'admin') {
      throw new Error('No permission for XP adjustment');
    }
    const previous = await tx.get(auditRef);
    if (previous.exists) {
      const data = previous.data();
      if (data.transactionId !== transactionId || data.operation !== operation ||
          data.reason !== reason.trim() || data.expectedRevision !== expectedRevision) {
        throw new Error('Request ID already used for another adjustment');
      }
      return { ...data.result, duplicate: true };
    }
    const snapshot = await tx.get(sourceRef);
    const source = snapshot.data() || {};
    if (!snapshot.exists || source.adjustmentOf || !(source.amount > 0) ||
        !Number.isSafeInteger(source.amount) || typeof source.userId !== 'string' ||
        !source.userId || source.userId.includes('/')) throw new Error('Invalid source reward');
    const targetSnapshot = await tx.get(db.collection('users').doc(source.userId));
    if (!targetSnapshot.exists || source.userId === actorId) {
      throw new Error('Cannot adjust this user');
    }
    const revision = source.adjustmentRevision || 0;
    if (revision !== expectedRevision ||
        source.status !== (operation === 'revoke' ? 'confirmed' : 'revoked')) {
      throw new Error('Reward changed; refresh before adjusting');
    }
    const statsRef = db.collection('xp_user_stats').doc(source.userId);
    const statsSnapshot = await tx.get(statsRef);
    const stats = statsSnapshot.data() || {};
    if (!statsSnapshot.exists || !Number.isSafeInteger(stats.xpTotal)) {
      throw new Error('Missing XP balance');
    }
    const delta = operation === 'revoke' ? -source.amount : source.amount;
    const total = stats.xpTotal + delta;
    if (!Number.isSafeInteger(total) || total < 0) throw new Error('Inconsistent XP balance');
    const historical = source.historicalCatchup === true && source.weekKey === null;
    if (!historical && !/^\d{4}-\d{2}-\d{2}$/.test(source.weekKey || '')) {
      throw new Error('Missing reward week');
    }
    const weekRef = db.collection('xp_user_weeks').doc(`${source.userId}_${source.weekKey}`);
    const weekSnapshot = historical ? null : await tx.get(weekRef);
    const week = weekSnapshot?.data() || {};
    const consumed = week.confirmedXp;
    const revoked = (week.revokedXp || 0) - delta;
    if (!historical && (!weekSnapshot.exists || !Number.isSafeInteger(consumed) ||
        !Number.isSafeInteger(revoked) || revoked < 0 || revoked > consumed)) {
      throw new Error('Inconsistent weekly XP balance');
    }
    const featuredRef = db.collection('xp_featured_achievements').doc(source.userId);
    const featured = source.action === 'achievement.unlock'
      ? (await tx.get(featuredRef)).data() : null;
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const correctionId = `adjustment_${id}`;
    const result = { transactionId, correctionId, delta, xpTotal: total,
      level: calculateLevel(total), revision: revision + 1, duplicate: false };
    // Weekly earning capacity stays consumed, preventing revoke/earn/restore farming.
    tx.update(statsRef, { xpTotal: total, level: result.level,
      ...(!historical && stats.weeklyXpWeek === source.weekKey ? {
        weeklyXp: consumed - revoked,
        weeklyConsumedXp: Math.max(0, consumed - (week.achievementBonusXp || 0)),
      } : {}),
      xpUpdatedAt: timestamp, xpLastTransactionId: correctionId });
    if (!historical) tx.update(weekRef, { revokedXp: revoked, updatedAt: timestamp });
    if (operation === 'revoke' && featured?.item?.id === source.objectId) {
      tx.set(featuredRef, {item: null});
    }
    tx.update(sourceRef, { status: operation === 'revoke' ? 'revoked' : 'confirmed',
      adjustmentRevision: result.revision, adjustmentReason: reason.trim(),
      [operation === 'revoke' ? 'revokedAt' : 'restoredAt']: timestamp });
    tx.create(db.collection('xp_transactions').doc(correctionId), {
      transactionId: correctionId, userId: source.userId, action: `xp.${operation}`,
      objectType: source.objectType, objectId: source.objectId,
      stage: String(result.revision), amount: delta, requestedAmount: delta,
      status: 'confirmed', adjustmentOf: transactionId, reason: reason.trim(),
      actorId, createdAt: timestamp, confirmedAt: timestamp,
      weekKey: source.weekKey || null,
    });
    tx.create(auditRef, { actorId, userId: source.userId, transactionId, operation,
      reason: reason.trim(), expectedRevision, before: stats.xpTotal, after: total,
      createdAt: timestamp, result });
    return result;
  });
}

module.exports = { adjustXp };
