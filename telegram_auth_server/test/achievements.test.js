const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
const now = {now: new Date('2026-09-08T12:00:00Z')};
function setup() {
  const f = fixture();
  const module = f.load('../lib/xp/achievements.js');
  return {...f, ...module};
}
test('featured achievement requires ownership and confirmation, supports replacement and removal', async () => {
  const f = setup();
  await assert.rejects(f.selectAchievement('tester', 'spots.1'), /not unlocked/);
  await assert.rejects(f.selectAchievement('tester', 'forged'), /Unknown/);
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('spots/one', {addedByUid: 'tester', status: 'approved'});
  f.rows.set('auth_test_metadata/tester', {creationTime: '2026-06-08T12:00:00Z'});
  await f.syncAchievements('tester', now);
  await f.selectAchievement('tester', 'spots.1');
  assert.equal(f.rows.get('xp_featured_achievements/tester').item.id, 'spots.1');
  assert.equal((await f.syncAchievements('tester', now)).selectedId, 'spots.1');
  await f.selectAchievement('tester', 'tenure.3');
  assert.equal(f.rows.get('xp_featured_achievements/tester').item.id, 'tenure.3');
  f.rows.set('users/other', {});
  await assert.rejects(f.selectAchievement('other', 'spots.1'), /not unlocked/);
  const reward = [...f.rows.values()].find(row => row.action === 'achievement.unlock' && row.objectId === 'spots.1');
  for (const status of ['pending', 'blocked', 'revoked']) {
    reward.status = status;
    await assert.rejects(f.selectAchievement('tester', 'spots.1'), /not unlocked/);
  }
  await f.selectAchievement('tester', null);
  assert.equal(f.rows.get('xp_featured_achievements/tester').item, null);
  f.rows.get('users/tester').banned = true;
  await assert.rejects(f.selectAchievement('tester', null), /unavailable/);
});

test('reward guide uses evaluator amounts and only own original confirmed rewards', async () => {
  const f = setup(); const rewards = f.load('../lib/xp/rewards.js');
  const catalog = rewards.rewardCatalog();
  assert.equal(catalog.length, 14);
  assert.equal(catalog.reduce((sum, row) => sum + row.xp, 0), 600);
  for (const item of catalog) for (const lang of ['en', 'ru', 'lv']) assert.ok(item.title[lang]);
  f.rows.set('xp_transactions/a', {userId: 'tester', action: 'spot.approved', amount: 50, status: 'confirmed'});
  f.rows.set('xp_transactions/b', {userId: 'tester', action: 'spot.approved', amount: 50, status: 'revoked'});
  f.rows.set('xp_transactions/c', {userId: 'tester', action: 'spot.approved', amount: 0, status: 'pending'});
  f.rows.set('xp_transactions/d', {userId: 'other', action: 'spot.approved', amount: 50, status: 'confirmed'});
  const result = await rewards.rewardProgress('tester');
  assert.equal(result.weekly.status, 'preview');
  assert.equal(result.weekly.items.length, 3);
  assert.equal(result.weekly.items.reduce((sum, item) => sum + item.xp, 0), 300);
  assert.ok(result.weekly.items.every(item => !('progress' in item)));
  const spot = result.items.find(item => item.id === 'spot.approved');
  assert.equal(spot.earnedXp, 50); assert.equal(spot.completed, 1); assert.equal(spot.pending, 1);
});
test('public achievements expose the full board and never expose private ledger data or award XP', async () => {
  const f = setup();
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('spots/one', {addedByUid: 'tester', status: 'approved'});
  await f.syncAchievements('tester', now);
  f.rows.set('users/viewer', {});
  f.rows.set('xp_transactions/private', {userId: 'tester', action: 'profile.avatar', status: 'confirmed', amount: 50, secret: 'private'});
  const before = JSON.stringify([...f.rows]);
  const result = await f.publicAchievements('viewer', 'tester');
  assert.equal(result.items.length, f.catalog().filter(i => i.category !== 'moderator').length);
  assert.equal(result.items.find(i=>i.id==='spots.5').status, 'locked');
  assert.equal(result.items.find(i=>i.id==='spots.5').progress, 1);
  assert.equal(result.items[0].id, 'spots.1');
  assert.equal(result.items[0].status, 'confirmed');
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.equal(JSON.stringify([...f.rows]), before);
  const reward = [...f.rows.values()].find(row => row.action === 'achievement.unlock');
  reward.status = 'revoked';
  assert.equal((await f.publicAchievements('viewer', 'tester')).items.find(i=>i.id==='spots.1').status, 'locked');
});

test('public achievements respect privacy, blocks and account status', async () => {
  for (const target of [{publicProfile: false}, {settings: {publicProfile: false}},
    {banned: true}, {deleted: true}, {blockedUserIds: ['viewer']}]) {
    const f = setup(); f.rows.set('users/viewer', {}); f.rows.set('users/tester', target);
    await assert.rejects(f.publicAchievements('viewer', 'tester'), /unavailable/);
  }
  const f = setup(); f.rows.set('users/viewer', {blockedUserIds: ['tester']});
  await assert.rejects(f.publicAchievements('viewer', 'tester'), /unavailable/);
  await assert.rejects(f.publicAchievements('missing', 'tester'), /unavailable/);
  await assert.rejects(f.publicAchievements('viewer', 'x/y'), /Invalid/);
});

test('achievement catalog has unique identities, approved rewards and three languages', () => {
  const f = setup(); const items = f.catalog();
  assert.equal(new Set(items.map(i => i.id)).size, items.length);
  assert.equal(items.length, 62);
  assert.equal(items.some(item => item.category === 'reports'), false);
  assert.equal(items.filter(i => i.category === 'tourist').length, 27);
  assert.equal(items.filter(i => i.category === 'spots').reduce((a,i) => a+i.xp,0), 1500);
  assert.equal(items.filter(i => i.category === 'moderator').reduce((a,i) => a+i.xp,0), 10500);
  for (const category of ['spots', 'visits', 'meets', 'topics', 'tenure', 'moderator', 'groups']) {
    const tiers = items.filter(item => item.category === category);
    assert.equal(tiers.length, 5);
    tiers.forEach((item, index) => {
      assert.equal(item.tier, index + 1);
      assert.ok(item.xp > 0 && item.xp <= 3000);
      if (index) assert.ok(item.threshold > tiers[index - 1].threshold);
    });
  }
  for (const i of items) for (const lang of ['en','ru','lv']) assert.ok(i.title[lang]);
});
test('achievement flag defaults off; no balance writes from viewing catalog', async () => {
  const f = setup();
  const result = await f.syncAchievements('tester', now);
  assert.equal(result.enabled, false);
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
});

test('achievement loading preserves award statuses and ignores unrelated XP history', async () => {
  const f = setup();
  for (let index = 0; index < 1000; index++) {
    f.rows.set(`xp_transactions/history-${index}`, {
      userId: 'tester', action: 'spot.approved', objectId: 'spots.1',
      status: 'confirmed', amount: 50,
    });
  }
  const statuses = ['confirmed', 'pending', 'blocked', 'revoked', 'locked'];
  const thresholds = [1, 5, 10, 25, 50];
  thresholds.slice(0, 4).forEach((threshold, index) => {
    f.rows.set(`xp_transactions/achievement-${index}`, {
      userId: 'tester', action: 'achievement.unlock', objectId: `spots.${threshold}`,
      status: statuses[index],
    });
  });
  f.rows.set('xp_transactions/other-user', {
    userId: 'someone-else', action: 'achievement.unlock', objectId: 'spots.50',
    status: 'confirmed',
  });
  f.rows.set('xp_featured_achievements/tester', {item: {id: 'spots.1'}});
  const before = JSON.stringify([...f.rows]);
  const result = await f.syncAchievements('tester', now);
  thresholds.forEach((threshold, index) => {
    assert.equal(result.items.find(item => item.id === `spots.${threshold}`).status, statuses[index]);
  });
  assert.equal(result.selectedId, 'spots.1');
  assert.equal(JSON.stringify([...f.rows]), before);
});

test('fifth tenure milestone awards once and preserves the previous four milestones', async () => {
  const f = setup();
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('auth_test_metadata/tester', {creationTime: '2023-09-08T12:00:00Z'});
  const first = await f.syncAchievements('tester', now);
  assert.equal(first.items.find(item => item.id === 'tenure.36').status, 'confirmed');
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 1650);
  await f.syncAchievements('tester', now);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 1650);
});
test('approved owned permanent spots count once and achievement retry cannot duplicate XP', async () => {
  const f = setup();
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('spots/one', {addedByUid: 'tester', ownerUid: 'tester', status: 'approved'});
  f.rows.set('spots/temp', {addedByUid: 'tester', status: 'approved', isTemporary: true});
  f.rows.set('spots/pending', {addedByUid: 'tester', status: 'pending'});
  const first = await f.syncAchievements('tester', now);
  assert.equal(first.items.find(i => i.id === 'spots.1').status, 'confirmed');
  await f.syncAchievements('tester', now);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 100);
  assert.equal(first.items.find(i => i.id === 'meets.1').status, 'confirmed');
  assert.equal(first.items.find(i => i.id === 'groups.10').available, false);
});
test('achievement awards in full above the weekly cap', async () => {
  const f = setup();
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('spots/one', {addedByUid: 'tester', status: 'approved'});
  f.rows.set('xp_user_weeks/tester_2026-09-07', {confirmedXp: 2999});
  const first = await f.syncAchievements('tester', now);
  assert.equal(first.items.find(i => i.id === 'spots.1').status, 'confirmed');
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').confirmedXp, 3049);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').achievementBonusXp, 50);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyConsumedXp, 2999);
});
test('membership uses Auth registration instead of editable profile timestamps', async () => {
  const f = setup(); f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.get('users/tester').createdAt = '2000-01-01';
  assert.equal((await f.syncAchievements('tester', now)).items.find(i => i.id === 'tenure.3').status, 'locked');
  f.rows.set('auth_test_metadata/tester', {creationTime: '2026-06-08T12:00:00Z'});
  assert.equal((await f.syncAchievements('tester', now)).items.find(i => i.id === 'tenure.3').status, 'confirmed');
});


test('retired reports are absent from personal/public boards and cannot be selected', async () => {
  const f = setup();
  f.rows.set('users/viewer', {});
  f.rows.set('xp_user_stats/tester', {xpTotal: 25});
  const {buildXpTransactionId} = f.load('../lib/xp/xp-engine.js');
  const id = buildXpTransactionId({userId: 'tester', action: 'achievement.unlock',
    objectType: 'achievement', objectId: 'reports.1', stage: 'unlocked', amount: 25});
  f.rows.set(`xp_transactions/${id}`, {userId: 'tester', action: 'achievement.unlock',
    objectId: 'reports.1', amount: 25, status: 'confirmed'});
  const before = JSON.stringify([...f.rows]);
  for (const result of [await f.syncAchievements('tester', now), await f.publicAchievements('viewer', 'tester')]) {
    assert.equal(result.items.some(item => item.category === 'reports'), false);
  }
  await assert.rejects(f.selectAchievement('tester', 'reports.1'), /Unknown achievement/);
  assert.equal(JSON.stringify([...f.rows]), before);
});

test('all active non-country achievements have five cumulative tiers', () => {
  const items=setup().catalog();
  for(const category of new Set(items.filter(i=>i.category!=='tourist').map(i=>i.category))){
    const group=items.filter(i=>i.category===category);
    assert.deepEqual(Array.from(group,i=>i.tier),[1,2,3,4,5]);
    assert.ok(group.every((item,index)=>index===0||item.threshold>group[index-1].threshold));
  }
});
test('50 spots unlock all five tiers without spending progress or awarding twice', async () => {
  const f=setup();f.rows.get('app_config/xp').achievements_enabled=true;
  for(let i=0;i<50;i++)f.rows.set('spots/s'+i,{addedByUid:'tester',status:'approved'});
  const first=await f.syncAchievements('tester',now);
  const spots=first.items.filter(i=>i.category==='spots');
  assert.ok(spots.every(i=>i.progress===50&&i.status==='confirmed'));
  const total=f.rows.get('xp_user_stats/tester').xpTotal;
  await f.syncAchievements('tester',now);assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,total);
  f.rows.set('users/viewer',{});
  const publicBoard=await f.publicAchievements('viewer','tester');
  assert.ok(publicBoard.items.filter(i=>i.category==='spots').every(i=>i.progress===50&&i.status==='confirmed'));
  f.rows.get('app_config/xp').achievements_enabled=false;
  assert.ok((await f.syncAchievements('tester',now)).items.filter(i=>i.category==='spots').every(i=>i.progress===50));
});
