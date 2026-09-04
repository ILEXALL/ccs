const { admin, db } = require('../lib/firebase-admin');

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 100;
const STATS_FETCH_LIMIT = 250;

function cleanString(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function numberValue(value, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function isActiveUser(user = {}) {
  return user && user.deleted !== true && user.banned !== true;
}

function publicProfileEnabled(user = {}) {
  const settings =
    user.settings && typeof user.settings === 'object' ? user.settings : {};

  return user.publicProfile !== false && settings.publicProfile !== false;
}

function limitFromBody(body = {}) {
  const parsed = Number(body.limit);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_LIMIT;
  }

  return Math.max(1, Math.min(MAX_LIMIT, Math.floor(parsed)));
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

function publicEntry(rank, statsDoc, userDoc) {
  const stats = statsDoc.data() || {};
  const user = userDoc.data() || {};
  const userId = cleanString(stats.userId, statsDoc.id);
  const username = cleanString(user.username, cleanString(user.name, 'ccs_driver'));

  return {
    rank,
    userId,
    username,
    name: cleanString(user.name, username),
    photoUrl: cleanString(user.photoUrl),
    avatarPath: cleanString(user.avatarPath),
    city: cleanString(user.city),
    country: cleanString(user.country),
    verified: user.verified === true || user.role === 'admin' || user.role === 'moderator',
    xpTotal: Math.max(0, numberValue(stats.xpTotal)),
    weeklyXp: Math.max(0, numberValue(stats.weeklyXp)),
    level: Math.max(1, numberValue(stats.level, 1)),
  };
}

async function loadLeaderboard(limit) {
  const statsSnapshot = await db
    .collection('xp_user_stats')
    .orderBy('xpTotal', 'desc')
    .limit(STATS_FETCH_LIMIT)
    .get();

  const statsDocs = statsSnapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    return data.xpBlocked !== true && numberValue(data.xpTotal) > 0;
  });
  const userSnapshots = await Promise.all(
    statsDocs.map((doc) => {
      const data = doc.data() || {};
      const userId = cleanString(data.userId, doc.id);
      return db.collection('users').doc(userId).get();
    }),
  );

  const entries = [];

  for (let index = 0; index < statsDocs.length; index += 1) {
    const userSnapshot = userSnapshots[index];
    if (!userSnapshot.exists) {
      continue;
    }

    const user = userSnapshot.data() || {};
    if (!isActiveUser(user) || !publicProfileEnabled(user)) {
      continue;
    }

    entries.push(publicEntry(entries.length + 1, statsDocs[index], userSnapshot));

    if (entries.length >= limit) {
      break;
    }
  }

  return entries;
}

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

    const entries = await loadLeaderboard(limitFromBody(req.body || {}));

    return res.status(200).json({
      ok: true,
      result: {
        entries,
        generatedAt: new Date().toISOString(),
      },
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: cleanString(error?.message, 'Could not load XP leaderboard'),
    });
  }
};
