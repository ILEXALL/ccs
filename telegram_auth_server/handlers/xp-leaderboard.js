const { admin, db } = require('../lib/firebase-admin');
const { weekKeyFor } = require('../lib/xp/xp-engine');

const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 100;
const STATS_FETCH_LIMIT = 10;
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

  if (!userSnapshot.exists || !isActiveUser(user)) {
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

function currentXpWeekKey(config) {
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
  return Math.max(0, numberValue(data.confirmedXp, numberValue(data.weeklyXp)) -
    numberValue(data.revokedXp));
}

function matchesSearch(user, search) {
  const username = cleanString(user.username, cleanString(user.name, 'ccs_driver'));
  return username.toLowerCase().includes(search);
}

function pageResult(matches, limit, weekKey) {
  const hasMore = matches.length > limit;
  return {
    entries: matches.slice(0, limit).map(match => match.entry),
    nextCursor: hasMore ? matches[limit - 1].cursor : null,
    hasMore,
    weekKey,
  };
}

function cursorFor(context, afterId, rank, score) {
  return { ...context, afterId, rank, score };
}

function readCursor(body, context) {
  const cursor = body.cursor;
  if (cursor == null) return null;
  if (typeof cursor !== 'object' || Array.isArray(cursor) ||
      cursor.period !== context.period || cursor.weekKey !== context.weekKey ||
      cursor.search !== context.search || typeof cursor.afterId !== 'string' ||
      !cursor.afterId || cursor.afterId.length > 1500 || cursor.afterId.includes('/') ||
      !Number.isSafeInteger(cursor.rank) || cursor.rank < 0 || cursor.rank > 10000000 ||
      !Number.isFinite(cursor.score) || cursor.score < 0) {
    const error = new Error('LEADERBOARD_CURSOR_EXPIRED');
    error.statusCode = 409;
    throw error;
  }
  return cursor;
}

async function cursorUserAvailable(userId, stats) {
  const snapshot = await db.collection('users').doc(userId).get();
  const user = snapshot.data() || {};
  return snapshot.exists && isActiveUser(user) && publicProfileEnabled(user) && stats.xpBlocked !== true;
}

async function loadAllTimeLeaderboard(limit, context, cursor) {
  const query = db.collection('xp_user_stats').orderBy('xpTotal', 'desc');
  const matches = [];
  let rank = cursor?.rank || 0;
  let after;
  if (cursor) {
    after = await db.collection('xp_user_stats').doc(cursor.afterId).get();
    if (!after.exists || after.data().xpTotal !== cursor.score ||
        !await cursorUserAvailable(cleanString(after.data().userId, after.id), after.data())) {
      const error = new Error('LEADERBOARD_CURSOR_EXPIRED');
      error.statusCode = 409;
      throw error;
    }
  }
  while (matches.length <= limit) {
    const batchSize = Math.min(STATS_FETCH_LIMIT, limit + 1 - matches.length);
    const pageQuery = query.limit(batchSize);
    const snapshot = await (after ? pageQuery.startAfter(after) : pageQuery).get();
    const docs = snapshot.docs.filter(doc => {
      const stats = doc.data() || {};
      return stats.xpBlocked !== true && numberValue(stats.xpTotal) > 0;
    });
    const users = docs.length ? await db.getAll(...docs.map(doc =>
      db.collection('users').doc(cleanString(doc.data().userId, doc.id)))) : [];
    for (let index = 0; index < docs.length; index++) {
      const user = users[index].data() || {};
      if (!users[index].exists || !isActiveUser(user) || !publicProfileEnabled(user)) continue;
      rank++;
      if (!matchesSearch(user, context.search)) continue;
      const stats = docs[index].data();
      const userId = cleanString(stats.userId, docs[index].id);
      matches.push({
        entry: publicEntry(rank, userId, stats, user,
          stats.weeklyXpWeek === context.weekKey ? numberValue(stats.weeklyXp) : 0),
        cursor: cursorFor(context, docs[index].id, rank, stats.xpTotal),
      });
      if (matches.length > limit) break;
    }
    if (snapshot.docs.length < batchSize) break;
    after = snapshot.docs[snapshot.docs.length - 1];
  }
  return pageResult(matches, limit, context.weekKey);
}

async function loadWeeklyLeaderboard(limit, context, cursor) {
  const {weekKey} = context;
  const weeksByUserId = new Map();
  // Traverse both schemas fully before ranking; a page boundary is not an XP cutoff.
  for (const field of ['weekKey', 'weeklyXpWeek']) {
    const baseQuery = db.collection('xp_user_weeks')
      .where(field, '==', weekKey).limit(WEEK_FETCH_LIMIT);
    let cursor;
    while (true) {
      const page = await (cursor ? baseQuery.startAfter(cursor) : baseQuery).get();
      for (const doc of page.docs) {
        const data = doc.data() || {};
        const userId = userIdFromWeekDoc(doc, data);
        const weeklyXp = xpFromWeekDoc(data);
        const existing = weeksByUserId.get(userId);

        if (!userId) {
          continue;
        }

        // A corrected canonical row, including zero, overrides stale legacy mirrors.
        const corrected = doc.id === `${userId}_${weekKey}` &&
          typeof data.revokedXp === 'number';
        if (!existing || corrected || (!existing.corrected && weeklyXp > existing.weeklyXp)) {
          weeksByUserId.set(userId, { userId, weeklyXp, corrected });
        }
      }
      if (page.docs.length < WEEK_FETCH_LIMIT) break;
      cursor = page.docs[page.docs.length - 1];
    }
  }

  const weeks = [...weeksByUserId.values()]
    .sort((first, second) => {
      if (second.weeklyXp !== first.weeklyXp) {
        return second.weeklyXp - first.weeklyXp;
      }
      return first.userId.localeCompare(second.userId);
    });

  // Keep the legacy/corrected-week reconciliation above. Only hydrate the
  // public profiles needed for this page, in batches of ten.
  const matches = [];
  let rank = cursor?.rank || 0;
  let start = 0;
  if (cursor) {
    const index = weeks.findIndex(week => week.userId === cursor.afterId && week.weeklyXp === cursor.score);
    const stats = (await db.collection('xp_user_stats').doc(cursor.afterId).get()).data() || {};
    if (index < 0 || !await cursorUserAvailable(cursor.afterId, stats)) {
      const error = new Error('LEADERBOARD_CURSOR_EXPIRED');
      error.statusCode = 409;
      throw error;
    }
    start = index + 1;
  }
  for (let offset = start; offset < weeks.length && matches.length <= limit;) {
    const batchSize = Math.min(STATS_FETCH_LIMIT, limit + 1 - matches.length);
    const batch = weeks.slice(offset, offset + batchSize).filter(week => week.weeklyXp > 0);
    offset += batchSize;
    if (!batch.length) break;
    const [statsSnapshots, userSnapshots] = await Promise.all([
      db.getAll(...batch.map(week => db.collection('xp_user_stats').doc(week.userId))),
      db.getAll(...batch.map(week => db.collection('users').doc(week.userId))),
    ]);
    for (let index = 0; index < batch.length; index++) {
      const week = batch[index];
      const user = userSnapshots[index].data() || {};
      const stats = statsSnapshots[index].data() || {};
      if (!userSnapshots[index].exists || !isActiveUser(user) ||
          !publicProfileEnabled(user) || stats.xpBlocked === true) continue;
      rank++;
      if (!matchesSearch(user, context.search)) continue;
      matches.push({
        entry: publicEntry(rank, week.userId, stats, user, week.weeklyXp),
        cursor: cursorFor(context, week.userId, rank, week.weeklyXp),
      });
      if (matches.length > limit) break;
    }
  }
  return pageResult(matches, limit, weekKey);
}

async function loadLeaderboard(limit, period, config, body) {
  const search = cleanString(body.search).replace(/^@/, '').trim().toLowerCase().slice(0, 30);
  const context = {period, weekKey: currentXpWeekKey(config), search};
  const cursor = readCursor(body, context);
  return period === 'weekly'
    ? loadWeeklyLeaderboard(limit, context, cursor)
    : loadAllTimeLeaderboard(limit, context, cursor);
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

    const configSnapshot = await db.collection('app_config').doc('xp').get();
    const config = configSnapshot.data() || {};
    const enabledUserIds = Array.isArray(config.enabledUserIds)
      ? config.enabledUserIds.filter((id) => typeof id === 'string').map((id) => id.trim())
      : [];
    if (config.levels_enabled !== true ||
        (!enabledUserIds.includes('*') && !enabledUserIds.includes(actor.uid))) {
      return res.status(403).json({ ok: false, error: 'XP_NOT_ENABLED' });
    }

    const body = req.body || {};
    const period = periodFromBody(body);
    const leaderboard = await loadLeaderboard(limitFromBody(body), period, config, body);

    return res.status(200).json({
      ok: true,
      result: {
        entries: leaderboard.entries,
        nextCursor: leaderboard.nextCursor,
        hasMore: leaderboard.hasMore,
        period,
        weekKey: leaderboard.weekKey,
        generatedAt: new Date().toISOString(),
      },
    });
  } catch (error) {
    return res.status(error.statusCode || 500).json({
      ok: false,
      error: cleanString(error?.message, 'Could not load XP leaderboard'),
    });
  }
};
