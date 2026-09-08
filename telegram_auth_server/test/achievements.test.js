const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
const now = {now: new Date('2026-09-08T12:00:00Z')};
function setup() {
  const f = fixture();
  const module = f.load('../lib/xp/achievements.js');
  return {...f, ...module};
}
test('achievement catalog has unique identities, approved rewards and three languages', () => {
  const f = setup(); const items = f.catalog();
  assert.equal(new Set(items.map(i => i.id)).size, items.length);
  assert.equal(items.filter(i => i.category === 'tourist').length, 27);
  assert.equal(items.filter(i => i.category === 'spots').reduce((a,i) => a+i.xp,0), 1500);
  assert.equal(items.filter(i => i.category === 'moderator').reduce((a,i) => a+i.xp,0), 7500);
  for (const i of items) for (const lang of ['en','ru','lv']) assert.ok(i.title[lang]);
});
test('achievement flag defaults off; no balance writes from viewing catalog', async () => {
  const f = setup();
  const result = await f.syncAchievements('tester', now);
  assert.equal(result.enabled, false);
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
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
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 50);
  assert.equal(first.items.find(i => i.id === 'groups.10').available, false);
});
test('achievement waits at cap and cannot settle while achievement flag is disabled', async () => {
  const f = setup();
  f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.set('spots/one', {addedByUid: 'tester', status: 'approved'});
  f.rows.set('xp_user_weeks/tester_2026-09-07', {confirmedXp: 2999});
  const first = await f.syncAchievements('tester', now);
  assert.equal(first.items.find(i => i.id === 'spots.1').status, 'pending');
  f.rows.get('app_config/xp').achievements_enabled = false;
  await f.awards.settlePendingXp('tester', {now: new Date('2026-09-14T12:00:00Z')});
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
});
test('membership uses Auth registration instead of editable profile timestamps', async () => {
  const f = setup(); f.rows.get('app_config/xp').achievements_enabled = true;
  f.rows.get('users/tester').createdAt = '2000-01-01';
  assert.equal((await f.syncAchievements('tester', now)).items.find(i => i.id === 'tenure.3').status, 'locked');
  f.rows.set('auth_test_metadata/tester', {creationTime: '2026-06-08T12:00:00Z'});
  assert.equal((await f.syncAchievements('tester', now)).items.find(i => i.id === 'tenure.3').status, 'confirmed');
});
