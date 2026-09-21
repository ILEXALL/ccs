const crypto = require('node:crypto');
const {db} = require('../firebase-admin');
const {taskCatalog} = require('./weekly-plan');
const {weekKeyFor, buildXpTransactionId} = require('./xp-engine');
const {awardXp, settlePendingXp} = require('./xp-firestore');
const EPOCH = '2026-09-21';
const unsupported = new Set(['accepted_photo_contributions', 'accepted_helpful_answers', 'helped_topic_authors']);
const catalog = taskCatalog().filter(t => !unsupported.has(t.metric)).map(t => ({...t, xp: t.xp * 2, available: true}));
const schedule = [];
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const milliseconds = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
function tasksForWeek(key) {
  const index = Math.round((Date.parse(key) - Date.parse(EPOCH)) / 604800000);
  if (!Number.isInteger(index) || index < 0 || index > 10000) return [];
  while (schedule.length <= index) {
    const n = schedule.length;
    const recent = new Set(schedule.slice(-3).flat().map(t => t.id));
    const previousMetrics = new Set((schedule[n - 1] || []).map(t => t.metric));
    const choices = [];
    for (const a of catalog.filter(t => t.difficulty === 0))
      for (const b of catalog.filter(t => t.difficulty === 1))
        for (const c of catalog.filter(t => t.difficulty === 2)) {
          const tasks = [a,b,c];
          if (tasks.some(t => recent.has(t.id)) || new Set(tasks.map(t => t.metric)).size < 3) continue;
          choices.push({tasks, score: tasks.filter(t => previousMetrics.has(t.metric)).length,
            random: hash(`weekly-live-v1|${n}|${tasks.map(t => t.id).join('|')}`)});
        }
    choices.sort((a,b) => a.score - b.score || a.random.localeCompare(b.random));
    if (!choices.length) throw new Error('Weekly schedule exhausted');
    schedule.push(choices[0].tasks);
  }
  return schedule[index].map(t => ({...t}));
}
function distinctDaysAtDifferentSpots(rows) {
  const days = [...new Set(rows.map(r => r.dayKey))];
  const matched = new Map();
  function assign(day, seen) {
    for (const row of rows.filter(r => r.dayKey === day)) {
      if (seen.has(row.spotId)) continue;
      seen.add(row.spotId);
      if (!matched.has(row.spotId) || assign(matched.get(row.spotId), seen)) {
        matched.set(row.spotId, day); return true;
      }
    }
    return false;
  }
  return days.filter(day => assign(day, new Set())).length;
}
function progress(task, rows, publications) {
  const spots = rows.filter(r => !r.event);
  const unique = key => new Set(spots.map(r => r[key]).filter(Boolean)).size;
  const fresh = spots.filter(r => r.firstVisit);
  const meets = rows.filter(r => r.event && r.ownerId !== r.userId);
  const complete = publications.filter(r => r.metadata?.weeklyComplete === true);
  const metrics = {
    verified_visits: unique('spotId'), first_visits: new Set(fresh.map(r => r.spotId)).size,
    distinct_visit_days: distinctDaysAtDifferentSpots(spots), visited_categories: Math.min(unique('spotId'), new Set(spots.flatMap(r => r.categories || []).filter(Boolean)).size),
    weekend_visits: spots.filter(r => [0,6].includes(new Date(r.dayKey).getUTCDay())).length,
    weekday_and_weekend_visits: spots.some(r => [0,6].includes(new Date(r.dayKey).getUTCDay())) && spots.some(r => ![0,6].includes(new Date(r.dayKey).getUTCDay())) && unique('spotId') >= 2 ? 2 : 0,
    first_visit_days: new Set(fresh.map(r => r.dayKey)).size,
    verified_meet_visits: new Set(meets.map(r => r.spotId)).size,
    meet_and_permanent_visit: (meets.length ? 1 : 0) + (spots.length ? 1 : 0),
    meet_and_two_first_visits: (meets.length ? 1 : 0) + Math.min(2, new Set(fresh.map(r => r.spotId)).size),
    new_complete_spots: complete.length,
    new_gallery_spots: publications.filter(r => r.metadata?.weeklyGallery === true).length,
    publish_and_two_visits: (complete.length ? 1 : 0) + Math.min(2, new Set(spots.filter(r => r.ownerId !== r.userId).map(r => r.spotId)).size),
  };
  return Math.min(task.target, metrics[task.metric] || 0);
}
function weeklyAward(userId, key, task) {
  return {userId, action: 'weekly.completed', objectType: 'weekly_task', objectId: `${key}_${task.id}`,
    stage: 'completed', amount: task.xp, metadata: {reason: task.title.en, title: task.title, assignmentWeek: key}};
}
async function syncWeeklyTasks(userId, options = {}) {
  const now = options.now || new Date();
  await settlePendingXp(userId, {now});
  const [visits, transactions, claims] = await Promise.all([
    db.collection('weekly_visit_records').where('userId', '==', userId).get(),
    db.collection('xp_transactions').where('userId', '==', userId).get(),
    db.collection('admin_reward_claims').where('userId', '==', userId).get(),
  ]);
  const rows = visits.docs.map(d => d.data());
  const publications = transactions.docs.map(d => d.data()).filter(r => r.action === 'spot.approved' && ['confirmed','pending'].includes(r.status));
  const keys = new Set([weekKeyFor(now), ...rows.map(r => r.weekKey), ...publications.map(r => r.metadata?.publicationWeek).filter(Boolean)]);
  for (const key of [...keys].sort()) {
    if (key > weekKeyFor(now)) continue;
    const evidence = rows.filter(r => r.weekKey === key);
    const daily = new Map(), seen = new Set(), paidSpots = [];
    for (const row of evidence.filter(r => !r.event).sort((a,b) => a.recordedAtMillis - b.recordedAtMillis || a.spotId.localeCompare(b.spotId))) {
      if (seen.has(row.spotId)) continue;
      seen.add(row.spotId);
      const count = daily.get(row.dayKey) || 0;
      if (count >= 3 || paidSpots.length >= 7) continue;
      daily.set(row.dayKey, count + 1);
      paidSpots.push(row.spotId);
    }
    for (const spotId of paidSpots) await awardXp({userId, action: 'visit.weekly', objectType: 'weekly_visit',
      objectId: `${key}_${spotId}`, stage: 'visited', amount: 50, metadata: {reason: 'Weekly spot visit', assignmentWeek: key, spotId}}, {now});
    const published = publications.filter(r => r.metadata?.publicationWeek === key);
    for (const task of tasksForWeek(key)) {
      if (progress(task, evidence, published) >= task.target) await awardXp(weeklyAward(userId, key, task), {now});
    }
  }
  for (const doc of claims.docs) {
    const c = doc.data();
    await awardXp({userId, action: 'admin_reward.completed', objectType: 'admin_reward', objectId: c.rewardId,
      stage: 'completed', amount: c.xp, metadata: {reason: c.title.en, title: c.title}}, {now});
  }
}
async function weeklyProgress(userId, options = {}) {
  const now = options.now || new Date();
  if (options.sync !== false) await syncWeeklyTasks(userId, {now});
  const key = weekKeyFor(now);
  const [visits, transactions, campaigns, userDoc, weekDoc, configDoc] = await Promise.all([
    db.collection('weekly_visit_records').where('userId', '==', userId).get(),
    db.collection('xp_transactions').where('userId', '==', userId).get(),
    db.collection('admin_rewards').where('enabled', '==', true).get(),
    db.collection('users').doc(userId).get(),
    db.collection('xp_user_weeks').doc(`${userId}_${key}`).get(),
    db.collection('app_config').doc('xp').get(),
  ]);
  const ledger = transactions.docs.map(d => d.data());
  const rows = visits.docs.map(d => d.data()).filter(r => r.weekKey === key);
  const pubs = ledger.filter(r => r.action === 'spot.approved' && ['confirmed','pending'].includes(r.status) && r.metadata?.publicationWeek === key);
  const state = award => ledger.find(r => r.transactionId === buildXpTransactionId(award) || (r.action === award.action && r.objectId === award.objectId));
  const items = tasksForWeek(key).map(t => {
    const record = state(weeklyAward(userId, key, t));
    return {...t, progress: progress(t, rows, pubs), status: record?.status || 'active'};
  });
  const adminItems = [];
  for (const doc of campaigns.docs) {
    const c = doc.data();
    if (c.startsAt > now.getTime() || c.endsAt <= now.getTime()) continue;
    const spot = (await db.collection('spots').doc(c.spotId).get()).data();
    if (!await eligibleTarget(spot, userDoc.data(), userId) || (spot.isTemporary && milliseconds(spot.expiresAt) <= now.getTime())) continue;
    const record = ledger.find(r => r.action === 'admin_reward.completed' && r.objectId === doc.id);
    adminItems.push({id: doc.id, title: c.title, xp: c.xp, target: 1, progress: record ? 1 : 0,
      status: record?.status || 'active', spotId: c.spotId, spotName: c.spotName, endsAt: c.endsAt});
  }
  const week = weekDoc.data() || {};
  const config = configDoc.data() || {};
  const enabled = config.levels_enabled === true && config.xp_awards_enabled === true &&
    ((config.enabledUserIds || []).includes('*') || (config.enabledUserIds || []).includes(userId));
  const pendingItems = ledger.filter(r => r.status === 'pending' && r.reason === 'WEEKLY_LIMIT_REACHED' &&
    ((r.action === 'weekly.completed' && r.metadata?.assignmentWeek !== key) ||
      (r.action === 'admin_reward.completed' && !adminItems.some(i => i.id === r.objectId))))
    .map(r => ({id: r.objectId, title: r.metadata.title, xp: r.requestedAmount, status: 'pending', target: 1, progress: 1}));
  return {visitXp: 50, dailyVisitLimit: 3, weeklyVisitLimit: 7, dwellSeconds: 300, status: enabled ? 'active' : 'disabled', weekKey: key, totalXp: 600, items, adminItems, pendingItems,
    limit: Math.min(3000, Number(config.weeklyLimit) || 3000), consumedXp: Math.max(0, (week.confirmedXp || 0) - (week.achievementBonusXp || 0)),
    pendingXp: ledger.filter(r => r.status === 'pending' && r.reason === 'WEEKLY_LIMIT_REACHED').reduce((n,r) => n + (Number(r.requestedAmount) || Number(r.amount) || 0), 0)};
}
async function eligibleTarget(spot, user, uid) {
  if (!spot || spot.deleted || spot.status !== 'approved') return false;
  if (spot.verifiedOnly && !user?.verified && !['admin','moderator'].includes(user?.role)) return false;
  if (spot.visibility !== 'group') return true;
  for (const id of (spot.sharedGroupIds || []).slice(0,8)) {
    const group = (await db.collection('chats').doc(id).get()).data();
    if (group?.isGroup === true && group.memberIds?.includes(uid)) return true;
  }
  return false;
}
module.exports = {EPOCH, tasksForWeek, progress, weeklyAward, syncWeeklyTasks, weeklyProgress};
