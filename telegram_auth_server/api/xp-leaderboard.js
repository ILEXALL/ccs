const { admin, db } = require('../lib/firebase-admin');
const { weekKeyFor } = require('../lib/xp/xp-engine');

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 100;
const STATS_FETCH_LIMIT = 250;
const WEEK_FETCH_LIMIT = 1000;
const LEADERBOARD_PERIODS = new Set(['all_time', 'weekly']);

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

function periodFromBody(body = {}) {
  const period = cleanString(body.period, 'all_time');
  return LEADERBOARD_PERIODS.has(period) ? period : 'all_time';
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

function publicEntry(rank, userId, stats, user, weeklyXpOverride) {
  const username = cleanString(
    user.username,
    cleanString(user.name, 'ccs_driver'),
  );

  return {
    rank,
    userId,
    username,
    name: cleanString(user.name, username),
    photoUrl: cleanString(user.photoUrl),
    avatarPath: cleanString(user.avatarPath),
    city: cleanString(user.city),
    country: cleanString(user.country),
    verified:
      user.verified === true || user.role === 'admin' || user.role === 'moderator',
    xpTotal: Math.max(0, numberValue(stats.xpTotal)),
    weeklyXp: Math.max(
      0,
      numberValue(weeklyXpOverride, numberValue(stats.weeklyXp)),
    ),
    level: Math.max(1, numberValue(stats.level, 1)),
  };
}

async function currentXpWeekKey() {
  const configSnapshot = await db.collection('app_config').doc('xp').get();
  const config = configSnapshot.data() || {};
  const timeZone = cleanString(
    config.timezone,
    cleanString(config.timeZone, 'Europe/Riga'),
  );
  return weekKeyFor(new Date(), timeZone);
}

function userIdFromWeekDoc(doc, data = {}) {
  const directUserId = cleanString(data.userId);
  if (directUserId) {
    return directUserId;
  }

  const docId = cleanString(doc.id);
  const weekDocMatch = docId.match(/^(.+)_\d{4}-\d{2}-\d{2}$/);
  return weekDocMatch ? weekDocMatch[1] : docId;
}

function xpFromWeekDoc(data = {}) {
  return Math.max(0, numberValue(data.confirmedXp, numberValue(data.weeklyXp)));
}

async function loadAllTimeLeaderboard(limit) {
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

    const stats = statsDocs[index].data() || {};
    const userId = cleanString(stats.userId, statsDocs[index].id);
    entries.push(publicEntry(entries.length + 1, userId, stats, user));

    if (entries.length >= limit) {
      break;
    }
  }

  return entries;
}

async function loadWeeklyLeaderboard(limit) {
  const weekKey = await currentXpWeekKey();
  const [weekKeySnapshot, legacyWeekSnapshot] = await Promise.all([
    db
      .collection('xp_user_weeks')
      .where('weekKey', '==', weekKey)
      .limit(WEEK_FETCH_LIMIT)
      .get(),
    db
      .collection('xp_user_weeks')
      .where('weeklyXpWeek', '==', weekKey)
      .limit(WEEK_FETCH_LIMIT)
      .get(),
  ]);

  const weeksByUserId = new Map();
  for (const doc of [...weekKeySnapshot.docs, ...legacyWeekSnapshot.docs]) {
    const data = doc.data() || {};
    const userId = userIdFromWeekDoc(doc, data);
    const weeklyXp = xpFromWeekDoc(data);
    const existing = weeksByUserId.get(userId);

    if (!userId || weeklyXp <= 0) {
      continue;
    }

    if (!existing || weeklyXp > existing.weeklyXp) {
      weeksByUserId.set(userId, { userId, weeklyXp });
    }
  }

  const weeks = [...weeksByUserId.values()]
    .sort((first, second) => {
      if (second.weeklyXp !== first.weeklyXp) {
        return second.weeklyXp - first.weeklyXp;
      }
      return first.userId.localeCompare(second.userId);
    })
    .slice(0, STATS_FETCH_LIMIT);

  const [statsSnapshots, userSnapshots] = await Promise.all([
    Promise.all(
      weeks.map((week) => {
        return db.collection('xp_user_stats').doc(week.userId).get();
      }),
    ),
    Promise.all(
      weeks.map((week) => {
        return db.collection('users').doc(week.userId).get();
      }),
    ),
  ]);

  const entries = [];

  for (let index = 0; index < weeks.length; index += 1) {
    const week = weeks[index];
    const userId = week.userId;
    const weeklyXp = week.weeklyXp;
    const userSnapshot = userSnapshots[index];
    const statsSnapshot = statsSnapshots[index];

    if (!userId || weeklyXp <= 0 || !userSnapshot.exists) {
      continue;
    }

    const user = userSnapshot.data() || {};
    const stats = statsSnapshot.exists ? statsSnapshot.data() || {} : {};
    if (
      !isActiveUser(user) ||
      !publicProfileEnabled(user) ||
      stats.xpBlocked === true
    ) {
      continue;
    }

    entries.push(publicEntry(entries.length + 1, userId, stats, user, weeklyXp));

    if (entries.length >= limit) {
      break;
    }
  }

  return { entries, weekKey };
}

async function loadLeaderboard(limit, period) {
  if (period === 'weekly') {
    return loadWeeklyLeaderboard(limit);
  }

  return {
    entries: await loadAllTimeLeaderboard(limit),
    weekKey: await currentXpWeekKey(),
  };
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

    const body = req.body || {};
    const period = periodFromBody(body);
    const leaderboard = await loadLeaderboard(limitFromBody(body), period);

    return res.status(200).json({
      ok: true,
      result: {
        entries: leaderboard.entries,
        period,
        weekKey: leaderboard.weekKey,
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
