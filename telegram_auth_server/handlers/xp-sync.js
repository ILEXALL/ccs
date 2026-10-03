const adminRewards = require('../lib/xp/admin-rewards');
const {grantXp, grantTarget, grantRequest} = require('../lib/xp/admin-grants');
const {syncWeeklyTasks} = require('../lib/xp/weekly-tasks');
const {assessLocation} = require('../lib/location-integrity');
const { admin, db } = require('../lib/firebase-admin');
const { adjustXp } = require('../lib/xp/xp-adjustments');
const { syncAchievements, selectAchievement, publicAchievements, recordCountryAchievement } = require('../lib/xp/achievements');
const { rewardProgress } = require('../lib/xp/rewards');
const { publicXpProfile, creatorSpotCount } = require('../lib/xp/public-profile');
const {
  awardManyXp,
  settlePendingXp,
  ensureXpConfig,
  evaluateFirstCarXp,
  evaluatePermanentSpotApprovalXp,
  evaluateProfileXp,
} = require('../lib/xp');

function cleanString(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function isStaff(user = {}) {
  return user.role === 'admin' || user.role === 'moderator';
}

function isAdmin(user = {}) {
  return user.role === 'admin';
}

function isActiveUser(user = {}) {
  return user && user.deleted !== true && user.banned !== true;
}

async function authenticatedUser(req) {
  const authorization = cleanString(req.headers.authorization);

  if (!authorization.startsWith('Bearer ')) {
    return null;
  }

  return admin.auth().verifyIdToken(authorization.slice('Bearer '.length), true);
}

async function actorContext(req) {
  const token = await authenticatedUser(req);

  if (!token?.uid) {
    return null;
  }

  const userSnapshot = await db.collection('users').doc(token.uid).get();
  const user = userSnapshot.data() || {};

  if (!userSnapshot.exists || !isActiveUser(user)) {
    return null;
  }

  return { uid: token.uid, user };
}

async function syncCurrentUser(actor) {
  const snapshot = await db.collection('users').doc(actor.uid).get();

  if (!snapshot.exists) {
    throw new Error('User not found');
  }

  const user = snapshot.data() || {};
  const awards = [
    ...evaluateProfileXp(actor.uid, user),
    ...evaluateFirstCarXp(actor.uid, user),
  ];

  await syncWeeklyTasks(actor.uid);
  return [...await settlePendingXp(actor.uid), ...await awardManyXp(awards)];
}

async function syncUser(actor, body) {
  if (!isStaff(actor.user)) {
    throw new Error('No permission to sync this user');
  }

  const userId = cleanString(body.userId);
  if (!userId) {
    throw new Error('Missing userId');
  }

  const snapshot = await db.collection('users').doc(userId).get();
  if (!snapshot.exists) {
    throw new Error('User not found');
  }

  const user = snapshot.data() || {};
  const awards = [
    ...evaluateProfileXp(userId, user),
    ...evaluateFirstCarXp(userId, user),
  ];

  return [...await settlePendingXp(userId), ...await awardManyXp(awards)];
}

async function syncSpot(actor, body) {
  const spotId = cleanString(body.spotId);
  if (!spotId) {
    throw new Error('Missing spotId');
  }

  const snapshot = await db.collection('spots').doc(spotId).get();
  if (!snapshot.exists) {
    throw new Error('Spot not found');
  }

  const spot = snapshot.data() || {};
  const authorUid = cleanString(spot.addedByUid, cleanString(spot.ownerUid));

  if (authorUid !== actor.uid && !isStaff(actor.user)) {
    throw new Error('No permission to sync this spot');
  }

  const awards = await awardManyXp(evaluatePermanentSpotApprovalXp(spotId, spot));
  if (authorUid) { await syncWeeklyTasks(authorUid); await syncAchievements(authorUid); }
  return awards;
}

const handlers = {
  admin_xp_grant_target: (actor, body) => grantRequest(grantTarget, actor.uid, body),
  admin_xp_grant: (actor, body) => grantRequest(grantXp, actor.uid, body),
  reset_spot_visit: async actor => {
    await db.runTransaction(async tx => tx.delete(db.collection('spot_visit_sessions').doc(actor.uid)));
    return {reset: true};
  },
  admin_reward_recipients: (actor, body) => adminRewards.recipients(actor.uid, body.id, body.cursor),
  admin_xp_audit: (actor, body) => adminRewards.xpAudit(actor.uid, body.cursor),
  admin_rewards: (actor) => adminRewards.listRewards(actor.uid),
  admin_reward_targets: (actor, body) => adminRewards.targetOptions(actor.uid, body.search, body.offset),
  admin_reward_create: (actor, body) => adminRewards.createReward(actor.uid, body),
  admin_reward_cancel: (actor, body) => adminRewards.cancelReward(actor.uid, body.id),
  location_check: async (actor, body) => ({accepted: await assessLocation(actor.uid, body)}),
  visit_country: async (actor, body) => {
    if (!await assessLocation(actor.uid, body)) throw new Error('Location could not be verified');
    return recordCountryAchievement(actor.uid, body);
  },
  creator_spots: (actor, body) => creatorSpotCount(actor.uid, body.userId),
  public_xp: (actor, body) => publicXpProfile(actor.uid, body.userId, body.section),
  public_achievements: (actor, body) => publicAchievements(actor.uid, body.userId),
  rewards: (actor) => rewardProgress(actor.uid),
  select_achievement: (actor, body) => selectAchievement(actor.uid, body.achievementId),
  achievements: (actor) => syncAchievements(actor.uid),
  adjust_xp: (actor, body) => adjustXp(actor.uid, body),
  ensure_config: async (actor) => {
    if (!isAdmin(actor.user)) {
      throw new Error('No permission to initialize XP config');
    }

    return ensureXpConfig();
  },
  sync_me: syncCurrentUser,
  sync_user: syncUser,
  sync_spot: syncSpot,
};

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  }

  try {
    const actor = await actorContext(req);

    if (!actor) {
      return res.status(401).json({ ok: false, error: 'Unauthorized' });
    }

    const action = cleanString(req.body?.action);
    const actionHandler = handlers[action];

    if (!actionHandler) {
      return res.status(400).json({ ok: false, error: 'Unknown action' });
    }

    const result = await actionHandler(actor, req.body || {});
    return res.status(200).json({ ok: true, result });
  } catch (error) {
    return res.status(403).json({
      ok: false,
      error: cleanString(error?.message, 'XP sync failed'),
    });
  }
};
