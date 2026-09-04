const { admin, db } = require('../firebase-admin');
const {
  XP_RULES_VERSION,
  buildXpTransactionId,
  buildXpUniqueKey,
  calculateLevel,
  defaultXpConfig,
  normalizeAwardInput,
  weekKeyFor,
} = require('./xp-engine');

async function awardXp(input, options = {}) {
  const normalized = normalizeAwardInput(input);
  const transactionId = buildXpTransactionId(normalized);
  const uniqueKey = buildXpUniqueKey(normalized);
  const transactionRef = db.collection('xp_transactions').doc(transactionId);
  const userRef = db.collection('users').doc(normalized.userId);
  const statsRef = db.collection('xp_user_stats').doc(normalized.userId);
  const configRef = db.collection('app_config').doc('xp');

  return db.runTransaction(async (transaction) => {
    const configSnapshot = await transaction.get(configRef);
    const config = xpConfigFromDocument(configSnapshot.data());
    const weekKey = weekKeyFor(options.now || new Date(), config.timeZone);
    const weekRef = db
      .collection('xp_user_weeks')
      .doc(`${normalized.userId}_${weekKey}`);

    const [existingSnapshot, userSnapshot, statsSnapshot, weekSnapshot] = await Promise.all([
      transaction.get(transactionRef),
      transaction.get(userRef),
      transaction.get(statsRef),
      transaction.get(weekRef),
    ]);

    if (existingSnapshot.exists) {
      const existing = existingSnapshot.data() || {};
      return {
        transactionId,
        userId: normalized.userId,
        awarded: false,
        duplicate: true,
        status: existing.status || 'confirmed',
        amount: numberValue(existing.amount),
        requestedAmount: numberValue(existing.requestedAmount) || normalized.amount,
        weekKey: stringValue(existing.weekKey) || weekKey,
        reason: 'DUPLICATE_XP_TRANSACTION',
      };
    }

    if (!config.levelsEnabled || !config.awardsEnabled) {
      return blockedResult(
        normalized,
        transactionId,
        weekKey,
        'XP_DISABLED_BY_CONFIG',
      );
    }

    if (!userEnabledForXp(normalized.userId, config)) {
      return blockedResult(
        normalized,
        transactionId,
        weekKey,
        'XP_USER_NOT_ENABLED',
      );
    }

    if (!userSnapshot.exists) {
      return blockedResult(normalized, transactionId, weekKey, 'USER_NOT_FOUND');
    }

    const user = userSnapshot.data() || {};
    const stats = statsSnapshot.data() || {};
    if (user.deleted === true || user.banned === true || user.xpBlocked === true) {
      transaction.create(
        transactionRef,
        transactionData(normalized, transactionId, uniqueKey, weekKey, {
          status: 'blocked',
          amount: 0,
          reason: 'USER_BLOCKED_OR_DELETED',
        }),
      );

      return blockedResult(
        normalized,
        transactionId,
        weekKey,
        'USER_BLOCKED_OR_DELETED',
      );
    }

    if (normalized.status !== 'confirmed') {
      transaction.create(
        transactionRef,
        transactionData(normalized, transactionId, uniqueKey, weekKey, {
          status: normalized.status,
          amount: normalized.amount,
        }),
      );

      return {
        transactionId,
        userId: normalized.userId,
        awarded: false,
        duplicate: false,
        status: normalized.status,
        amount: normalized.amount,
        requestedAmount: normalized.amount,
        weekKey,
      };
    }

    const week = weekSnapshot.data() || {};
    const currentWeekXp = numberValue(week.confirmedXp);
    const remainingWeeklyXp = Math.max(0, config.weeklyLimit - currentWeekXp);

    if (remainingWeeklyXp <= 0) {
      transaction.create(
        transactionRef,
        transactionData(normalized, transactionId, uniqueKey, weekKey, {
          status: 'blocked',
          amount: 0,
          reason: 'WEEKLY_LIMIT_REACHED',
        }),
      );

      return blockedResult(
        normalized,
        transactionId,
        weekKey,
        'WEEKLY_LIMIT_REACHED',
      );
    }

    const appliedAmount = Math.min(normalized.amount, remainingWeeklyXp);
    const currentTotalXp = statsSnapshot.exists
      ? numberValue(stats.xpTotal)
      : numberValue(user.xpTotal);
    const nextTotalXp = currentTotalXp + appliedAmount;
    const nextLevel = calculateLevel(nextTotalXp);
    const partialReason =
      appliedAmount < normalized.amount ? 'WEEKLY_LIMIT_PARTIAL' : undefined;

    transaction.create(
      transactionRef,
      transactionData(normalized, transactionId, uniqueKey, weekKey, {
        status: 'confirmed',
        amount: appliedAmount,
        reason: partialReason,
      }),
    );

    if (
      appliedAmount > 0 &&
      notificationPreferenceEnabled(user, 'xpNotifications')
    ) {
      const notificationRef = db
        .collection('user_notifications')
        .doc(`xp_${transactionId}`);

      transaction.set(
        notificationRef,
        xpNotificationData(normalized, transactionId, appliedAmount, weekKey),
        { merge: true },
      );
    }

    transaction.set(
      weekRef,
      {
        userId: normalized.userId,
        weekKey,
        confirmedXp: currentWeekXp + appliedAmount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: weekSnapshot.exists
          ? week.createdAt || admin.firestore.FieldValue.serverTimestamp()
          : admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    transaction.set(
      statsRef,
      {
        userId: normalized.userId,
        xpTotal: nextTotalXp,
        level: nextLevel,
        weeklyXp: currentWeekXp + appliedAmount,
        weeklyXpWeek: weekKey,
        xpBlocked: user.xpBlocked === true,
        xpUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        xpLastTransactionId: transactionId,
        createdAt: statsSnapshot.exists
          ? stats.createdAt || admin.firestore.FieldValue.serverTimestamp()
          : admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      transactionId,
      userId: normalized.userId,
      awarded: appliedAmount > 0,
      duplicate: false,
      status: 'confirmed',
      amount: appliedAmount,
      requestedAmount: normalized.amount,
      weekKey,
      reason: partialReason,
      xpTotal: nextTotalXp,
      level: nextLevel,
    };
  });
}

async function awardManyXp(awards, options = {}) {
  const results = [];

  for (const award of awards) {
    results.push(await awardXp(award, options));
  }

  return results;
}

async function ensureXpConfig() {
  const configRef = db.collection('app_config').doc('xp');
  const snapshot = await configRef.get();

  if (snapshot.exists) {
    return {
      created: false,
      config: xpConfigFromDocument(snapshot.data()),
    };
  }

  const defaults = defaultXpConfig();
  await configRef.set({
    levels_enabled: defaults.levelsEnabled,
    xp_awards_enabled: defaults.awardsEnabled,
    enabledUserIds: defaults.enabledUserIds,
    weeklyLimit: defaults.weeklyLimit,
    timezone: defaults.timeZone,
    rulesVersion: defaults.rulesVersion,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    created: true,
    config: defaults,
  };
}

function xpConfigFromDocument(data) {
  const defaults = defaultXpConfig();
  if (!data) {
    return defaults;
  }

  const weeklyLimit = numberValue(data.weeklyLimit);

  return {
    levelsEnabled: data.levels_enabled === true,
    awardsEnabled: data.xp_awards_enabled === true,
    enabledUserIds: stringArray(data.enabledUserIds, 500),
    weeklyLimit: weeklyLimit > 0 ? weeklyLimit : defaults.weeklyLimit,
    timeZone: stringValue(data.timezone) || defaults.timeZone,
    rulesVersion: stringValue(data.rulesVersion) || XP_RULES_VERSION,
  };
}

function userEnabledForXp(userId, config) {
  const enabledUserIds = config.enabledUserIds || [];
  return enabledUserIds.includes('*') || enabledUserIds.includes(userId);
}

function notificationPreferenceEnabled(user, preferenceKey) {
  if (!user || typeof user !== 'object') {
    return true;
  }

  if (typeof user[preferenceKey] === 'boolean') {
    return user[preferenceKey];
  }

  const settings =
    user.settings && typeof user.settings === 'object' ? user.settings : {};
  if (typeof settings[preferenceKey] === 'boolean') {
    return settings[preferenceKey];
  }

  return true;
}

function xpNotificationData(input, transactionId, amount, weekKey) {
  return {
    userId: input.userId,
    type: 'xp_reward',
    title: 'XP reward',
    body: `+${amount} XP`,
    xpTransactionId: transactionId,
    xpAction: input.action,
    xpObjectType: input.objectType,
    xpObjectId: input.objectId,
    xpAmount: amount,
    weekKey,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAtMillis: Date.now(),
  };
}

function transactionData(input, transactionId, uniqueKey, weekKey, result) {
  return {
    transactionId,
    uniqueKey,
    userId: input.userId,
    action: input.action,
    objectType: input.objectType,
    objectId: input.objectId,
    stage: input.stage,
    amount: result.amount,
    requestedAmount: input.amount,
    status: result.status,
    weekKey,
    reason: result.reason || null,
    rulesVersion: XP_RULES_VERSION,
    metadata: input.metadata || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    confirmedAt:
      result.status === 'confirmed'
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
    rejectedAt:
      result.status === 'rejected'
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
    revokedAt:
      result.status === 'revoked'
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
    blockedAt:
      result.status === 'blocked'
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
  };
}

function blockedResult(input, transactionId, weekKey, reason) {
  return {
    transactionId,
    userId: input.userId,
    awarded: false,
    duplicate: false,
    status: 'blocked',
    amount: 0,
    requestedAmount: input.amount,
    weekKey,
    reason,
  };
}

function numberValue(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function stringArray(value, limit = 500) {
  if (!Array.isArray(value)) {
    return [];
  }

  return [
    ...new Set(
      value
        .filter((item) => typeof item === 'string')
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  ].slice(0, limit);
}

module.exports = {
  awardXp,
  awardManyXp,
  ensureXpConfig,
  xpConfigFromDocument,
};
