const test = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../lib/xp/xp-engine');
const { evaluateProfileXp, evaluateFirstCarXp } = require('../lib/xp/profile-garage-xp');
const { evaluatePermanentSpotApprovalXp } = require('../lib/xp/spot-xp');

const { fixture } = require('./support');

const award = (overrides = {}) => ({ userId: 'tester', action: 'profile.avatar',
  objectType: 'profile', objectId: 'tester', stage: 'avatar', amount: 50, ...overrides });
const monday = { now: new Date('2026-09-07T12:00:00Z') };

test('all 100 level boundaries and XP immediately below each boundary', () => {
  for (let level = 1; level <= 100; level++) {
    const threshold = 25 * (level - 1) ** 2;
    assert.equal(engine.xpRequiredForLevel(level), threshold);
    assert.equal(engine.calculateLevel(threshold), level);
    if (level > 1) assert.equal(engine.calculateLevel(threshold - 1), level - 1);
  }
  assert.equal(engine.calculateLevel(1000000), 100);
});

test('Riga week changes at Monday midnight in summer, winter and DST transitions', () => {
  for (const [date, expected] of [
    ['2026-09-06T20:59:59Z', '2026-08-31'], ['2026-09-06T21:00:00Z', '2026-09-07'],
    ['2026-01-04T21:59:59Z', '2025-12-29'], ['2026-01-04T22:00:00Z', '2026-01-05'],
    ['2026-03-29T21:00:00Z', '2026-03-30'], ['2026-10-25T22:00:00Z', '2026-10-26'],
  ]) assert.equal(engine.weekKeyFor(new Date(date)), expected);
});

test('profile rewards and full-profile bonus total 250 XP', () => {
  assert.equal(evaluateProfileXp('tester', {}).length, 0);
  const awards = evaluateProfileXp('tester', {
    photoUrl: 'avatar', bio: 'a'.repeat(20), city: 'Riga', telegram: 'tester',
  });
  assert.deepEqual(awards.map((x) => x.amount), [50, 40, 30, 30, 100]);
});

test('first car totals 250 XP; repeated photo does not earn gallery bonus', () => {
  const car = { name: 'Car', description: 'a'.repeat(20), photoPath: 'a',
    photoPaths: ['a', 'b', 'c'], buildType: 'stock', tags: ['daily'] };
  assert.equal(evaluateFirstCarXp('tester', { garage: [car] })
    .reduce((sum, x) => sum + x.amount, 0), 250);
  car.photoPaths = ['a', 'a', 'a'];
  assert.equal(evaluateFirstCarXp('tester', { garage: [car] })
    .some((x) => x.action === 'garage.first_car_gallery'), false);
});

test('only approved permanent spots earn XP; full content totals 100 XP', () => {
  const spot = { addedByUid: 'tester', status: 'approved', description: 'a'.repeat(20),
    photoUrl: 'a', photoUrls: ['a', 'b', 'c'] };
  assert.equal(evaluatePermanentSpotApprovalXp('spot', spot)
    .reduce((sum, x) => sum + x.amount, 0), 100);
  for (const status of ['pending', 'edited', 'rejected']) {
    assert.equal(evaluatePermanentSpotApprovalXp('spot', { ...spot, status }).length, 0);
  }
  assert.equal(evaluatePermanentSpotApprovalXp('spot', { ...spot, isTemporary: true }).length, 0);
});

test('repeat award preserves totals and creates only one notification', async () => {
  const f = fixture();
  assert.equal((await f.awards.awardXp(award(), monday)).amount, 50);
  assert.equal((await f.awards.awardXp(award(), monday)).duplicate, true);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 50);
  assert.equal([...f.rows.keys()].filter((key) => key.startsWith('user_notifications/')).length, 1);
});

test('one-time award waits in full and settles exactly once next week', async () => {
  const f = fixture({ 'xp_user_weeks/tester_2026-09-07': { confirmedXp: 2990 } });
  const first = await f.awards.awardXp(award(), monday);
  assert.equal(first.status, 'pending');
  assert.equal(first.awarded, false);
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').confirmedXp, 2990);
  assert.equal((await f.awards.awardXp(award(), monday)).duplicate, true);
  const settled = await f.awards.settlePendingXp('tester', {
    now: new Date('2026-09-14T12:00:00Z'),
  });
  assert.equal(settled[0].amount, 50);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 50);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-14').confirmedXp, 50);
  assert.equal((await f.awards.awardXp(award(), monday)).duplicate, true);
  assert.equal([...f.rows.keys()].filter(k => k.startsWith('user_notifications/')).length, 1);
});

test('pending entitlement uses stored amount and respects disabled flags', async () => {
  const f = fixture({ 'xp_user_weeks/tester_2026-09-07': { confirmedXp: 3000 } });
  await f.awards.awardXp(award(), monday);
  f.rows.get('app_config/xp').levels_enabled = false;
  const nextWeek = { now: new Date('2026-09-14T12:00:00Z') };
  assert.equal((await f.awards.settlePendingXp('tester', nextWeek))[0].awarded, false);
  f.rows.get('app_config/xp').levels_enabled = true;
  assert.equal((await f.awards.awardXp(award({amount: 999}), nextWeek)).amount, 50);
});

test('pending review is not automatically confirmed by weekly settlement', async () => {
  const f = fixture();
  await f.awards.awardXp(award({status: 'pending'}), monday);
  assert.equal((await f.awards.settlePendingXp('tester', monday)).length, 0);
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
});

test('deleted or rejected spots cannot receive deferred XP', async () => {
  for (const spot of [null, {status: 'rejected', addedByUid: 'tester'}]) {
    const f = fixture({ 'xp_user_weeks/tester_2026-09-07': {confirmedXp: 3000} });
    const input = award({action: 'spot.approved', objectType: 'spot', objectId: 's'});
    await f.awards.awardXp(input, monday);
    if (spot) f.rows.set('spots/s', spot);
    const results = await f.awards.settlePendingXp('tester', {
      now: new Date('2026-09-14T12:00:00Z'),
    });
    assert.equal(results[0].reason, 'SPOT_NO_LONGER_ELIGIBLE');
    assert.equal(f.rows.has('xp_user_stats/tester'), false);
  }
});

test('repeatable awards still obey the cap without becoming deferred', async () => {
  const f = fixture({'xp_user_weeks/tester_2026-09-07': {confirmedXp: 2990}});
  const input = award({action: 'test.repeatable'});
  assert.equal((await f.awards.awardXp(input, monday)).amount, 10);
  assert.equal((await f.awards.awardXp({...input, stage: 'next'}, monday)).status, 'blocked');
  assert.equal((await f.awards.settlePendingXp('tester', monday)).length, 0);
});

test('non-testers and banned, deleted or XP-blocked users get no XP', async () => {
  for (const user of [{ banned: true }, { deleted: true }, { xpBlocked: true }]) {
    const f = fixture({ 'users/tester': user });
    assert.equal((await f.awards.awardXp(award(), monday)).awarded, false);
    assert.equal(f.rows.has('xp_user_stats/tester'), false);
  }
  const f = fixture({ 'users/outsider': {} });
  assert.equal((await f.awards.awardXp(award({ userId: 'outsider' }), monday)).reason, 'XP_USER_NOT_ENABLED');
});

test('either disabled XP flag prevents awards', async () => {
  for (const flag of ['levels_enabled', 'xp_awards_enabled']) {
    const f = fixture();
    f.rows.get('app_config/xp')[flag] = false;
    assert.equal((await f.awards.awardXp(award(), monday)).reason, 'XP_DISABLED_BY_CONFIG');
  }
});

test('notification opt-out at root or settings suppresses notification but preserves XP', async () => {
  for (const user of [{ xpNotifications: false }, { settings: { xpNotifications: false } }]) {
    const f = fixture({ 'users/tester': user });
    assert.equal((await f.awards.awardXp(award(), monday)).amount, 50);
    assert.equal([...f.rows.keys()].some((key) => key.startsWith('user_notifications/')), false);
  }
});

async function leaderboard(f, uid, period) {
  const response = { status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; }, setHeader() {} };
  await f.load('../api/xp-leaderboard.js')({ method: 'POST',
    headers: { authorization: `Bearer ${uid}` }, body: { period, limit: 100 } }, response);
  return response;
}

test('enabled tester can load both leaderboard periods', async () => {
  const f = fixture();
  const weekKey = engine.weekKeyFor(new Date());
  f.rows.set('xp_user_stats/tester', { xpTotal: 500, level: 5 });
  f.rows.set(`xp_user_weeks/tester_${weekKey}`, { userId: 'tester', weekKey, confirmedXp: 75 });
  for (const period of ['all_time', 'weekly']) {
    const response = await leaderboard(f, 'tester', period);
    assert.equal(response.code, 200);
    assert.equal(response.body.result.entries[0].userId, 'tester');
    if (period === 'weekly') assert.equal(response.body.result.entries[0].weeklyXp, 75);
  }
});

test('private profiles do not appear in either leaderboard period', async () => {
  const f = fixture({ 'users/tester': { publicProfile: false } });
  const weekKey = engine.weekKeyFor(new Date());
  f.rows.set('xp_user_stats/tester', { xpTotal: 500, level: 5 });
  f.rows.set(`xp_user_weeks/tester_${weekKey}`, { userId: 'tester', weekKey, confirmedXp: 75 });
  for (const period of ['all_time', 'weekly']) {
    const response = await leaderboard(f, 'tester', period);
    assert.equal(response.code, 200);
    assert.equal(response.body.result.entries.length, 0);
  }
});

test('weekly leaderboard includes highest scorer beyond the first 1000 document IDs', async () => {
  const f = fixture();
  const weekKey = engine.weekKeyFor(new Date());
  for (let i = 0; i < 1000; i++) {
    const userId = `a${String(i).padStart(4, '0')}`;
    f.rows.set(`users/${userId}`, { name: userId });
    f.rows.set(`xp_user_stats/${userId}`, { xpTotal: 1, level: 1 });
    f.rows.set(`xp_user_weeks/${userId}_${weekKey}`, { userId, weekKey, confirmedXp: 1 });
  }
  f.rows.set('users/z_winner', { name: 'Winner' });
  f.rows.set('xp_user_stats/z_winner', { xpTotal: 3000, level: 11 });
  f.rows.set(`xp_user_weeks/z_winner_${weekKey}`, { userId: 'z_winner', weekKey, confirmedXp: 3000 });
  const response = await leaderboard(f, 'tester', 'weekly');
  assert.equal(response.code, 200);
  assert.equal(response.body.result.entries[0]?.userId, 'z_winner');
});

test('XP leaderboard denies a user outside the enabled tester list', async () => {
  const f = fixture({ 'users/outsider': { name: 'Outsider' } });
  f.rows.set('xp_user_stats/tester', { xpTotal: 500, level: 5 });
  for (const period of ['all_time', 'weekly']) {
    const response = await leaderboard(f, 'outsider', period);
    assert.equal(response.code, 403);
    assert.equal(response.body.error, 'XP_NOT_ENABLED');
  }
});

test('missing or disabled configuration denies leaderboard access', async () => {
  for (const config of [undefined, {}, { levels_enabled: false, enabledUserIds: ['tester'] },
    { levels_enabled: true, enabledUserIds: [] }]) {
    const f = fixture();
    if (config === undefined) f.rows.delete('app_config/xp');
    else f.rows.set('app_config/xp', config);
    assert.equal((await leaderboard(f, 'tester', 'weekly')).code, 403);
  }
});

test('public rollout wildcard allows access even when awarding is paused', async () => {
  const f = fixture({ 'users/outsider': { name: 'Outsider' } });
  f.rows.get('app_config/xp').enabledUserIds = [' * '];
  f.rows.get('app_config/xp').xp_awards_enabled = false;
  assert.equal((await leaderboard(f, 'outsider', 'all_time')).code, 200);
});

test('missing, banned and deleted users cannot access leaderboard', async () => {
  for (const user of [undefined, { banned: true }, { deleted: true }]) {
    const f = fixture();
    if (user === undefined) f.rows.delete('users/tester');
    else f.rows.set('users/tester', user);
    assert.equal((await leaderboard(f, 'tester', 'weekly')).code, 401);
  }
});

test('legacy weekly pages are complete and users in both schemas are not duplicated', async () => {
  const f = fixture();
  const weekKey = engine.weekKeyFor(new Date());
  for (let i = 0; i < 2000; i++) {
    f.rows.set(`xp_user_weeks/a${String(i).padStart(4, '0')}`, {
      userId: `a${i}`, weeklyXpWeek: weekKey, weeklyXp: 1,
    });
  }
  f.rows.set('users/z_winner', { name: 'Winner' });
  f.rows.set('xp_user_weeks/z_winner', { userId: 'z_winner', weeklyXpWeek: weekKey, weeklyXp: 3000 });
  f.rows.set(`xp_user_weeks/z_winner_${weekKey}`, { userId: 'z_winner', weekKey, confirmedXp: 2900 });
  const response = await leaderboard(f, 'tester', 'weekly');
  assert.equal(response.code, 200);
  assert.equal(response.body.result.entries.length, 1);
  assert.equal(response.body.result.entries[0].userId, 'z_winner');
  assert.equal(response.body.result.entries[0].weeklyXp, 3000);
});

test('weekly ranking continues past 250 hidden leaders to fill top 100', async () => {
  const f = fixture();
  const weekKey = engine.weekKeyFor(new Date());
  for (let i = 0; i < 350; i++) {
    const userId = `u${String(i).padStart(4, '0')}`;
    f.rows.set(`users/${userId}`, { publicProfile: i >= 250 });
    f.rows.set(`xp_user_weeks/${userId}_${weekKey}`, { userId, weekKey, confirmedXp: 3000 - i });
  }
  const response = await leaderboard(f, 'tester', 'weekly');
  assert.equal(response.code, 200);
  const entries = response.body.result.entries;
  assert.equal(entries.length, 100);
  assert.equal(entries[0].userId, 'u0250');
  assert.equal(entries[99].rank, 100);
});
