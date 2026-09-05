const test = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./support');

function setup() {
  const f = fixture({
    'users/admin': {role: 'admin'}, 'users/mod': {role: 'moderator'},
    'xp_user_stats/tester': {xpTotal: 100, level: 3, weeklyXp: 100, weeklyXpWeek: '2026-09-07'},
    'xp_user_weeks/tester_2026-09-07': {userId: 'tester', weekKey: '2026-09-07', confirmedXp: 100},
    'xp_transactions/reward': {userId: 'tester', amount: 50, status: 'confirmed',
      action: 'profile.avatar', objectType: 'profile', objectId: 'tester', weekKey: '2026-09-07'},
  });
  return {...f, adjust: f.load('../lib/xp/xp-adjustments.js').adjustXp};
}
const request = {transactionId: 'reward', requestId: 'one', reason: 'Confirmed error',
  operation: 'revoke', expectedRevision: 0};

test('revoke and restore create signed corrections and recalculate level once', async () => {
  const f = setup();
  const result = await f.adjust('admin', request);
  assert.equal(result.xpTotal, 50);
  assert.equal(result.level, 2);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 50);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').confirmedXp, 100);
  assert.equal(f.rows.get(`xp_transactions/${result.correctionId}`).amount, -50);
  assert.equal((await f.adjust('admin', request)).duplicate, true);
  const restored = await f.adjust('admin', {...request, requestId: 'two',
    operation: 'restore', expectedRevision: 1});
  assert.equal(restored.xpTotal, 100);
  assert.equal(restored.level, 3);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 100);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').revokedXp, 0);
  assert.equal([...f.rows.keys()].filter(k => k.startsWith('xp_admin_audit/')).length, 2);
  await assert.rejects(f.adjust('admin', {...request, requestId: 'stale'}), /refresh/);
});

test('permissions, reasons and request collision are enforced', async () => {
  const f = setup();
  for (const actor of ['tester', 'mod', 'missing']) {
    await assert.rejects(f.adjust(actor, request), /permission/);
  }
  await assert.rejects(f.adjust('admin', {...request, reason: ' '}), /details/);
  await f.adjust('admin', request);
  await assert.rejects(f.adjust('admin', {...request, reason: 'Different'}), /already used/);
  f.rows.get('users/admin').banned = true;
  await assert.rejects(f.adjust('admin', request), /permission/);
});

test('self adjustments, pending rewards and inconsistent balances are rejected', async () => {
  const f = setup();
  f.rows.get('users/tester').role = 'admin';
  await assert.rejects(f.adjust('tester', request), /this user/);
  f.rows.get('xp_transactions/reward').status = 'pending';
  await assert.rejects(f.adjust('admin', request), /refresh/);
  f.rows.get('xp_transactions/reward').status = 'confirmed';
  f.rows.get('xp_user_stats/tester').xpTotal = 10;
  await assert.rejects(f.adjust('admin', request), /balance/);
  assert.equal([...f.rows.keys()].some(k => k.startsWith('xp_admin_audit/')), false);
});

test('corrections cannot themselves be corrected and client amounts are ignored', async () => {
  const f = setup();
  const result = await f.adjust('admin', {...request, amount: 99999, userId: 'admin'});
  assert.equal(result.delta, -50);
  await assert.rejects(f.adjust('admin', {...request, requestId: 'nested',
    transactionId: result.correctionId}), /source/);
});

test('authenticated endpoint exposes adjustment only to admin', async () => {
  const f = setup();
  for (const [uid, expected] of [['tester', 403], ['admin', 200]]) {
    const res = { status(code) { this.code = code; return this; },
      json(body) { this.body = body; return this; }, setHeader() {} };
    await f.load('../api/xp-sync.js')({method: 'POST',
      headers: {authorization: `Bearer ${uid}`}, body: {...request, action: 'adjust_xp'}}, res);
    assert.equal(res.code, expected);
  }
});

test('revocation cannot free earning capacity; new awards preserve net weekly XP', async () => {
  const f = setup();
  const week = f.rows.get('xp_user_weeks/tester_2026-09-07');
  week.confirmedXp = 2990;
  f.rows.get('xp_user_stats/tester').xpTotal = 2990;
  await f.adjust('admin', request);
  const reward = {userId: 'tester', action: 'profile.city', objectType: 'profile',
    objectId: 'tester', stage: 'city', amount: 30};
  const options = {now: new Date('2026-09-08T12:00:00Z')};
  assert.equal((await f.awards.awardXp(reward, options)).status, 'pending');
  await f.awards.awardXp({...reward, action: 'test.repeatable', amount: 10}, options);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').confirmedXp, 3000);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 2950);
  await f.adjust('admin', {...request, requestId: 'restore', operation: 'restore', expectedRevision: 1});
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 3000);
  assert.equal((await f.awards.awardXp(reward, options)).status, 'pending');
});

test('past-week correction leaves current-week cache unchanged', async () => {
  const f = setup();
  Object.assign(f.rows.get('xp_user_stats/tester'), {weeklyXpWeek: '2026-09-14', weeklyXp: 20});
  await f.adjust('admin', request);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 20);
  assert.equal(f.rows.get('xp_user_weeks/tester_2026-09-07').revokedXp, 50);
});

test('missing weekly ledger prevents a partial correction', async () => {
  const f = setup();
  f.rows.delete('xp_user_weeks/tester_2026-09-07');
  await assert.rejects(f.adjust('admin', request), /weekly XP balance/);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 100);
  assert.equal(f.rows.get('xp_transactions/reward').status, 'confirmed');
});

test('weekly ranking ignores stale legacy mirrors after full revocation and restores once', async () => {
  const f = setup();
  const {weekKeyFor} = require('../lib/xp/xp-engine');
  const weekKey = weekKeyFor(new Date());
  f.rows.get('xp_transactions/reward').weekKey = weekKey;
  f.rows.set(`xp_user_weeks/tester_${weekKey}`, {userId: 'tester', weekKey, confirmedXp: 50});
  f.rows.set('xp_user_weeks/legacy', {userId: 'tester', weeklyXpWeek: weekKey, weeklyXp: 50});
  async function entries() {
    const res = {status(code) {this.code = code; return this;},
      json(body) {this.body = body; return this;}, setHeader() {}};
    await f.load('../api/xp-leaderboard.js')({method: 'POST',
      headers: {authorization: 'Bearer tester'}, body: {period: 'weekly', limit: 100}}, res);
    assert.equal(res.code, 200);
    return res.body.result.entries;
  }
  await f.adjust('admin', request);
  assert.equal((await entries()).length, 0);
  await f.adjust('admin', {...request, requestId: 'restore', operation: 'restore', expectedRevision: 1});
  assert.equal((await entries())[0].weeklyXp, 50);
});
