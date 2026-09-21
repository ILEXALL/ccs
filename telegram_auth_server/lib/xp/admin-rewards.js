const {db} = require('../firebase-admin');
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
async function requireAdmin(tx, uid) {
  const user = (await tx.get(db.collection('users').doc(uid))).data();
  if (!user || user.role !== 'admin' || user.banned || user.deleted) throw new Error('Admin access required');
}
async function listRewards(uid) {
  await db.runTransaction(tx => requireAdmin(tx, uid));
  const docs = await db.collection('admin_rewards').get();
  return {items: docs.docs.map(d => ({...d.data(), id: d.id})).sort((a,b) => b.createdAt - a.createdAt)};
}
function normalizeSearch(value) {
  return String(value || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().trim();
}
async function targetOptions(uid, search = '', offset = 0) {
  await db.runTransaction(tx => requireAdmin(tx, uid));
  const query = normalizeSearch(search).slice(0, 100);
  const start = Number.isSafeInteger(offset) && offset >= 0 ? offset : 0;
  const docs = await db.collection('spots').where('status', '==', 'approved').get();
  const items = docs.docs.filter(d => !d.data().deleted)
    .map(d => ({id: d.id, name: String(d.data().name || d.id), event: d.data().isTemporary === true}))
    .filter(item => !query || normalizeSearch(item.name).includes(query) || normalizeSearch(item.id) === query)
    .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
  return {items: items.slice(start, start + 5), nextOffset: start + 5 < items.length ? start + 5 : null};
}
async function createReward(uid, input, now = Date.now()) {
  if (!validId(input.id) || !validId(input.spotId) || !Number.isInteger(input.xp) || input.xp < 1 || input.xp > 3000 ||
    !Number.isFinite(input.startsAt) || !Number.isFinite(input.endsAt) || input.startsAt < now - 86400000 || input.endsAt > now + 90 * 86400000 || input.endsAt <= Math.max(now, input.startsAt) ||
    input.endsAt - Math.max(now, input.startsAt) > 90 * 86400000) throw new Error('Invalid reward: XP 1–3000, duration up to 90 days');
  const title = {};
  for (const lang of ['en','ru','lv']) {
    if (typeof input.title?.[lang] !== 'string' || !input.title[lang].trim() || input.title[lang].trim().length > 160) throw new Error('Title required in three languages');
    title[lang] = input.title[lang].trim();
  }
  return db.runTransaction(async tx => {
    await requireAdmin(tx, uid);
    const ref = db.collection('admin_rewards').doc(input.id);
    const existing = await tx.get(ref);
    const spot = (await tx.get(db.collection('spots').doc(input.spotId))).data();
    if (!spot || spot.deleted || spot.status !== 'approved') throw new Error('Approved target required');
    if (spot.isTemporary) {
      const starts = spot.startsAt?.toMillis?.() ?? Number(spot.startsAt);
      const ends = spot.expiresAt?.toMillis?.() ?? Number(spot.expiresAt);
      if (!Number.isFinite(ends) || ends <= Math.max(now, input.startsAt) || (Number.isFinite(starts) && starts >= input.endsAt)) throw new Error('Reward dates must overlap an active event');
    }
    if (existing.exists) {
      const old = existing.data();
      if (old.createdBy !== uid || old.spotId !== input.spotId || old.xp !== input.xp || old.startsAt !== input.startsAt || old.endsAt !== input.endsAt || JSON.stringify(old.title) !== JSON.stringify(title)) throw new Error('Reward ID already used');
      return {id: input.id};
    }
    tx.create(ref, {title, xp: input.xp, spotId: input.spotId, spotName: String(spot.name || input.spotId),
      event: spot.isTemporary === true, startsAt: input.startsAt, endsAt: input.endsAt,
      createdAt: now, createdBy: uid, enabled: true});
    return {id: input.id};
  });
}
async function cancelReward(uid, id, now = Date.now()) {
  if (!validId(id)) throw new Error('Invalid reward');
  return db.runTransaction(async tx => {
    await requireAdmin(tx, uid);
    const ref = db.collection('admin_rewards').doc(id);
    if (!(await tx.get(ref)).exists) throw new Error('Reward not found');
    tx.update(ref, {enabled: false, cancelledAt: now, cancelledBy: uid});
    return {id, enabled: false};
  });
}
module.exports = {listRewards, targetOptions, createReward, cancelReward};
