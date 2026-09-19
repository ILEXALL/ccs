const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
const {buildXpTransactionId} = require('../lib/xp/xp-engine');
const now = {now: new Date('2026-09-07T12:00:00Z')};
const bonus = {userId: 'tester', action: 'achievement.unlock', objectType: 'achievement',
  objectId: 'spots.50', stage: 'unlocked', amount: 750};
const normal = {userId: 'tester', action: 'ordinary.test', objectType: 'test',
  objectId: 'one', stage: 'done', amount: 3000};
function setup() {
  const f = fixture({'users/admin': {role: 'admin'}});
  f.rows.get('app_config/xp').achievements_enabled = true;
  return f;
}

test('3000 ordinary plus 750 achievement, in either order, counts 3750 once', async () => {
  for (const sequence of [[normal, bonus], [bonus, normal]]) {
    const f = setup();
    for (const award of sequence) await f.awards.awardXp(award, now);
    assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3750);
    assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 3750);
    assert.equal(f.rows.get('xp_user_stats/tester').weeklyConsumedXp, 3000);
    assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').achievementBonusXp, 750);
    await f.awards.awardXp(bonus, now);
    await f.awards.awardXp({...normal, objectId: 'second'}, now);
    assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3750);
  }
});

test('caller-supplied exemption cannot bypass cap for ordinary rewards', async () => {
  const f = setup();
  await f.awards.awardXp(normal, now);
  const result = await f.awards.awardXp({...normal, objectId: 'forged', weeklyCapExempt: true}, now);
  assert.equal(result.awarded, false);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3000);
});

test('bonus respects all feature flags and tester eligibility', async () => {
  for (const config of [{achievements_enabled: false}, {levels_enabled: false},
    {xp_awards_enabled: false}, {enabledUserIds: []}]) {
    const f = setup(); Object.assign(f.rows.get('app_config/xp'), config);
    assert.equal((await f.awards.awardXp(bonus, now)).awarded, false);
    assert.equal(f.rows.has('xp_user_stats/tester'), false);
  }
});

test('legacy pending achievement settles above cap once, but never while disabled', async () => {
  const f = setup();
  await f.awards.awardXp(normal, now);
  const id = buildXpTransactionId(bonus);
  f.rows.set(`xp_transactions/${id}`, {...bonus, requestedAmount: 750, status: 'pending',
    reason: 'WEEKLY_LIMIT_REACHED', weekKey: '2026-08-31'});
  f.rows.get('app_config/xp').achievements_enabled = false;
  await f.awards.settlePendingXp('tester', now);
  assert.equal(f.rows.get('xp_transactions/' + id).status, 'pending');
  f.rows.get('app_config/xp').achievements_enabled = true;
  await f.awards.settlePendingXp('tester', now);
  await f.awards.settlePendingXp('tester', now);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3750);
  assert.equal(f.rows.get('xp_transactions/' + id).weeklyCapExempt, true);
});

test('revoking and restoring a bonus changes ranking XP but never refills capacity', async () => {
  const f = setup();
  await f.awards.awardXp(normal, now);
  await f.awards.awardXp(bonus, now);
  const adjust = f.load('../lib/xp/xp-adjustments.js').adjustXp;
  const request = {transactionId: buildXpTransactionId(bonus), requestId: 'revoke',
    operation: 'revoke', expectedRevision: 0, reason: 'Test correction'};
  await adjust('admin', request);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 3000);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyConsumedXp, 3000);
  await f.awards.awardXp({...normal, objectId: 'extra'}, now);
  await f.awards.awardXp(bonus, now);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3000);
  await adjust('admin', {...request, requestId: 'restore', operation: 'restore', expectedRevision: 1});
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3750);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyConsumedXp, 3000);
});

test('next week resets ordinary quota, but not achievement identity', async () => {
  const f = setup();
  await f.awards.awardXp(normal, now);
  await f.awards.awardXp(bonus, now);
  const next = {now: new Date('2026-09-14T12:00:00Z')};
  await f.awards.awardXp(bonus, next);
  await f.awards.awardXp({...normal, objectId: 'next-week'}, next);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 6750);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 3000);
});

test('ordinary limit cannot be raised above 3000 by server config', async () => {
  const f = setup();
  f.rows.get('app_config/xp').weeklyLimit = 9000;
  await f.awards.awardXp({...normal, amount: 9000}, now);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3000);
});

test('legacy confirmed totals are not retroactively re-awarded or reclassified', async () => {
  const f = setup();
  f.rows.set('xp_user_weeks/tester_2026-09-07', {confirmedXp: 3000});
  f.rows.set('xp_user_stats/tester', {xpTotal: 3000});
  f.rows.set('xp_transactions/' + buildXpTransactionId(bonus), {...bonus, status: 'confirmed'});
  await f.awards.awardXp(bonus, now);
  assert.equal((await f.awards.awardXp({...normal, objectId: 'extra'}, now)).awarded, false);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 3000);
});
