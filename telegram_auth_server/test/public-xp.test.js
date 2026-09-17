const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');

test('public XP returns safe confirmed history and aggregates without writes', async () => {
  const f = fixture({'users/viewer': {}});
  const {publicXpProfile} = f.load('../lib/xp/public-profile.js');
  f.rows.set('xp_user_stats/tester', {xpTotal: 100, xpBlocked: true, secret: 'hidden'});
  const row = {userId: 'tester', action: 'spot.approved', status: 'confirmed', amount: 50,
    objectId: 'private-spot', reason: 'hidden', metadata: {secret: 'hidden'}, createdAtMillis: 10};
  f.rows.set('xp_transactions/a', row);
  f.rows.set('xp_transactions/b', {...row, status: 'pending'});
  f.rows.set('xp_transactions/c', {...row, status: 'revoked'});
  f.rows.set('xp_transactions/d', {...row, userId: 'viewer'});
  f.rows.set('xp_transactions/e', {...row, adjustmentOf: 'a'});
  f.rows.set('xp_transactions/f', {...row, action: 'admin.reward'});
  const before = JSON.stringify([...f.rows]);
  assert.equal(JSON.stringify(await publicXpProfile('viewer', 'tester')), '{"xpTotal":100}');
  const history = await publicXpProfile('viewer', 'tester', 'history');
  assert.equal(history.items.length, 1);
  assert.equal(history.items[0].amount, 50);
  assert.equal(JSON.stringify(history).includes('hidden'), false);
  assert.equal(JSON.stringify(history).includes('private-spot'), false);
  const rewards = await publicXpProfile('viewer', 'tester', 'rewards');
  assert.equal(rewards.items.find(item => item.id === 'spot.approved').completed, 1);
  assert.ok(rewards.items.every(item => item.pending === 0));
  assert.equal(JSON.stringify([...f.rows]), before);
});

test('all public XP sections enforce privacy, blocking and active accounts', async () => {
  for (const section of ['stats', 'rewards', 'history']) {
    for (const target of [{publicProfile: false}, {settings: {publicProfile: false}},
      {banned: true}, {deleted: true}, {blockedUserIds: ['viewer']}]) {
      const f = fixture({'users/viewer': {}, 'users/tester': target});
      await assert.rejects(f.load('../lib/xp/public-profile.js').publicXpProfile('viewer', 'tester', section), /unavailable/);
    }
    for (const actor of [{banned: true}, {deleted: true}, {blockedUserIds: ['tester']}]) {
      const f = fixture({'users/viewer': actor});
      await assert.rejects(f.load('../lib/xp/public-profile.js').publicXpProfile('viewer', 'tester', section), /unavailable/);
    }
  }
});

test('public history returns latest 100 confirmed entries only', async () => {
  const f = fixture({'users/viewer': {}});
  for (let i = 0; i < 110; i++) f.rows.set(`xp_transactions/${i}`, {
    userId: 'tester', action: 'spot.photo', status: 'confirmed', amount: 25, createdAtMillis: i,
  });
  const result = await f.load('../lib/xp/public-profile.js').publicXpProfile('viewer', 'tester', 'history');
  assert.equal(result.items.length, 100);
  assert.equal(result.items[0].createdAtMillis, 109);
  assert.equal(result.items[99].createdAtMillis, 10);
});

test('public XP endpoint uses authenticated identity, not a client-supplied actor', async () => {
  const f = fixture({'users/viewer': {blockedUserIds: ['tester']}});
  const handler = f.load('../handlers/xp-sync.js');
  const res = {code: 0, body: null, setHeader() {},
    status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; }};
  await handler({method: 'POST', headers: {authorization: 'Bearer viewer'},
    body: {action: 'public_xp', userId: 'tester', actorId: 'tester', section: 'history'}}, res);
  assert.equal(res.code, 403);
  await handler({method: 'POST', headers: {}, body: {action: 'public_xp', userId: 'tester'}}, res);
  assert.equal(res.code, 401);
});
