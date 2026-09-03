const { admin, db } = require('../lib/firebase-admin');
const {
  awardManyXp,
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

  return admin.auth().verifyIdToken(authorization.slice('Bearer '.length));
}

async function actorContext(req) {
  const token = await authenticatedUser(req);

  if (!token?.uid) {
    return null;
  }

  const userSnapshot = await db.collection('users').doc(token.uid).get();
  const user = userSnapshot.data() || {};

  if (!isActiveUser(user)) {
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

  return awardManyXp(awards);
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

  return awardManyXp(awards);
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

  return awardManyXp(evaluatePermanentSpotApprovalXp(spotId, spot));
}

const handlers = {
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
