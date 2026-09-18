const {createdSpotCount} = require('./spot-counts');
const { db, admin } = require('../firebase-admin');
const { awardManyXp } = require('./xp-firestore');
const { buildXpTransactionId } = require('./xp-engine');

const categories = [
  ['spots', ['Spots', 'Споты', 'Vietas'], [[1,50],[5,100],[10,200],[25,400],[50,750]], 'count'],
  ['visits', ['Visits', 'Посещения', 'Apmeklējumi'], [[1,25],[10,100],[25,200],[50,350],[100,600]], 'count'],
  ['meets', ['Organized meets', 'Организованные миты', 'Organizētas tikšanās'], [[1,50],[5,150],[10,300],[25,600],[50,1000]], 'count'],
  ['topics', ['Active topics', 'Активные темы', 'Aktīvas tēmas'], [[1,25],[5,100],[10,200],[25,400],[50,750]], 'count'],
  ['tenure', ['CCS membership', 'Стаж CCS', 'Dalība CCS'], [[3,50],[6,100],[12,250],[24,500],[36,750]], 'months'],
  ['moderator', ['Moderator service', 'Стаж модератора', 'Moderatora stāžs'], [[3,1000],[6,1500],[12,2000],[24,3000],[36,3000]], 'months'],
  ['groups', ['Group owner', 'Владелец группы', 'Grupas īpašnieks'], [[10,100],[25,250],[50,500],[100,1000],[250,1500]], 'members_month'],
];
// Retired badges remain recognized in XP history; balances are never rewritten.
const retiredAchievementIds = ['reports.1', 'reports.5', 'reports.10', 'reports.25', 'reports.50'];

const countries = [
  ['AT','austria','Austria','Австрия','Austrija'],['BE','belgium','Belgium','Бельгия','Beļģija'],
  ['BG','bulgaria','Bulgaria','Болгария','Bulgārija'],['HR','croatia','Croatia','Хорватия','Horvātija'],
  ['CY','cyprus','Cyprus','Кипр','Kipra'],['CZ','czechia','Czechia','Чехия','Čehija'],
  ['DK','denmark','Denmark','Дания','Dānija'],['EE','estonia','Estonia','Эстония','Igaunija'],
  ['FI','finland','Finland','Финляндия','Somija'],['FR','france','France','Франция','Francija'],
  ['DE','germany','Germany','Германия','Vācija'],['GR','greece','Greece','Греция','Grieķija'],
  ['HU','hungary','Hungary','Венгрия','Ungārija'],['IE','ireland','Ireland','Ирландия','Īrija'],
  ['IT','italy','Italy','Италия','Itālija'],['LV','latvia','Latvia','Латвия','Latvija'],
  ['LT','lithuania','Lithuania','Литва','Lietuva'],['LU','luxembourg','Luxembourg','Люксембург','Luksemburga'],
  ['MT','malta','Malta','Мальта','Malta'],['NL','netherlands','Netherlands','Нидерланды','Nīderlande'],
  ['PL','poland','Poland','Польша','Polija'],['PT','portugal','Portugal','Португалия','Portugāle'],
  ['RO','romania','Romania','Румыния','Rumānija'],['SK','slovakia','Slovakia','Словакия','Slovākija'],
  ['SI','slovenia','Slovenia','Словения','Slovēnija'],['ES','spain','Spain','Испания','Spānija'],
  ['SE','sweden','Sweden','Швеция','Zviedrija'],
];
const title = ([en, ru, lv]) => ({en, ru, lv});
function catalog() {
  return [
    ...categories.flatMap(([category, names, tiers, unit]) => tiers.map(([threshold, xp], index) => ({
      id: `${category}.${threshold}`, category, title: title(names), threshold, xp, unit, tier: index + 1,
      available: ['spots', 'tenure'].includes(category),
    }))),
    ...countries.map(([code, asset, ...names]) => ({id: `tourist.${code}`, category: 'tourist',
      title: title(names), threshold: 1, xp: 75, unit: 'country', tier: 1,
      asset: `assets/achievements/${asset}.png`, available: false})),
  ];
}

function completedMonths(created, now) {
  const start = new Date(created);
  if (!Number.isFinite(start.getTime()) || now < start) return 0;
  let months = (now.getUTCFullYear() - start.getUTCFullYear()) * 12 + now.getUTCMonth() - start.getUTCMonth();
  const anniversary = new Date(start);
  anniversary.setUTCDate(1);
  anniversary.setUTCFullYear(now.getUTCFullYear(), now.getUTCMonth(),
    Math.min(start.getUTCDate(), new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0)).getUTCDate()));
  if (now < anniversary) months--;
  return Math.max(0, months);
}

async function achievementProgress(userId, now = new Date()) {
  const [spots, authUser] = await Promise.all([
    createdSpotCount(userId), admin.auth().getUser(userId),
  ]);
  return {spots, tenure: completedMonths(authUser.metadata.creationTime, now)};
}

function boardItems(earned, progress) {
  const totals = {...progress};
  for (const item of catalog()) {
    if (earned.get(item.id)?.status === 'confirmed') {
      totals[item.category] = Math.max(totals[item.category] || 0, item.threshold);
    }
  }
  return catalog().map(item => ({...item, progress: totals[item.category] || 0,
    status: earned.get(item.id)?.status === 'confirmed' ? 'confirmed' : earned.get(item.id)?.status || 'locked'}));
}

async function syncAchievements(userId, options = {}) {
  const config = (await db.collection('app_config').doc('xp').get()).data() || {};
  const enabled = config.achievements_enabled === true;
  const progress = await achievementProgress(userId, options.now || new Date());
  if (enabled) {
    await awardManyXp(catalog().filter(item => item.available && progress[item.category] >= item.threshold)
      .map(item => ({userId, action: 'achievement.unlock', objectType: 'achievement',
        objectId: item.id, stage: 'unlocked', amount: item.xp,
        metadata: {achievementId: item.id}})), options);
  }
  // Fetch only achievement awards, after awarding so new unlocks appear in the
  // same response. Unrelated XP history can grow without slowing this screen.
  const [transactions, featuredSnapshot] = await Promise.all([
    db.collection('xp_transactions').where('userId', '==', userId)
      .where('action', '==', 'achievement.unlock').get(),
    db.collection('xp_featured_achievements').doc(userId).get(),
  ]);
  const earned = new Map(transactions.docs.map(doc => doc.data())
    .filter(data => data.action === 'achievement.unlock').map(data => [data.objectId, data]));
  const featured = featuredSnapshot.data();
  return { enabled, selectedId: featured?.item?.id || null, items: boardItems(earned, progress) };
}

async function selectAchievement(userId, achievementId) {
  const item = catalog().find(entry => entry.id === achievementId);
  if (achievementId !== null && !item) throw new Error('Unknown achievement');
  return db.runTransaction(async tx => {
    const user = (await tx.get(db.collection('users').doc(userId))).data();
    if (!user || user.deleted === true || user.banned === true) throw new Error('User unavailable');
    if (item) {
      const id = buildXpTransactionId({userId, action: 'achievement.unlock', objectType: 'achievement',
        objectId: item.id, stage: 'unlocked', amount: item.xp});
      const award = (await tx.get(db.collection('xp_transactions').doc(id))).data();
      if (award?.status !== 'confirmed' || award.userId !== userId) throw new Error('Achievement not unlocked');
    }
    tx.set(db.collection('xp_featured_achievements').doc(userId), {item: item || null});
    return {selectedId: item?.id || null};
  });
}

async function assertPublicXpAccess(actorId, userId) {
  if (typeof userId !== 'string' || !userId || userId.includes('/')) throw new Error('Invalid user');
  const [actorDoc, targetDoc] = await db.getAll(db.collection('users').doc(actorId), db.collection('users').doc(userId));
  const actor = actorDoc.data();
  const target = targetDoc.data();
  if (!actor || actor.banned === true || actor.deleted === true || !target ||
      target.banned === true || target.deleted === true ||
      target.publicProfile === false || target.settings?.publicProfile === false ||
      (target.blockedUserIds || []).includes(actorId) || (actor.blockedUserIds || []).includes(userId)) {
    throw new Error('Profile unavailable');
  }
}

async function publicAchievements(actorId, userId) {
  await assertPublicXpAccess(actorId, userId);
  const items = catalog();
  // Read only known achievement awards; never serialize private XP transactions.
  const awards = await db.getAll(...items.map(item => db.collection('xp_transactions').doc(
    buildXpTransactionId({userId, action: 'achievement.unlock', objectType: 'achievement',
      objectId: item.id, stage: 'unlocked', amount: item.xp}))));
  const progress = await achievementProgress(userId);
  const earned = new Map();
  items.forEach((item, index) => {
    const award = awards[index].data();
    // Public viewers see earned/locked states only, never moderation reasons.
    if (award?.status === 'confirmed' && award.userId === userId) earned.set(item.id, {status: 'confirmed'});
  });
  return {enabled: true, public: true, items: boardItems(earned, progress)};

}

module.exports = { catalog, retiredAchievementIds, completedMonths, syncAchievements, selectAchievement, publicAchievements, assertPublicXpAccess };
