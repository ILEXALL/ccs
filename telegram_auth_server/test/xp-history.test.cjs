const test = require('node:test');
const assert = require('node:assert/strict');
const {publicHistory} = require('../lib/xp/history');
const history = (rows, offset) => publicHistory(rows, new Map(), new Set(['badge']), offset);

test('all confirmed award sources appear without exposing private ledger fields', () => {
  const actions = ['admin.grant', 'admin_reward.completed', 'weekly_task.completed', 'future.reward'];
  const rows = actions.map((action, i) => ({action, objectType: 'admin_reward',
    status: 'confirmed', amount: 100, createdAtMillis: i + 1,
    reason: 'private reason', actorId: 'admin', userId: 'recipient',
    objectId: 'private-task', metadata: {reason: 'private reason'}}));
  const result = history(rows);
  assert.deepEqual(result.items.map(row => row.action), [...actions].reverse());
  for (const row of result.items) {
    assert.deepEqual(Object.keys(row).sort(), ['achievementId', 'action', 'amount', 'createdAtMillis', 'objectType']);
    assert.equal(row.achievementId, '');
  }
});

test('public history excludes pending, rejected, and negative rows', () => {
  assert.equal(history([
    {status: 'pending', amount: 100}, {status: 'rejected', amount: 100},
    {status: 'confirmed', amount: -100}, {status: 'confirmed', amount: NaN},
    {status: 'confirmed', action: 'adjustment.restore', amount: 100},
  ]).items.length, 1);
});

test('older awards remain accessible beyond the first hundred', () => {
  const rows = Array.from({length: 205}, (_, i) => ({status: 'confirmed',
    amount: 1, action: `award.${i}`, createdAt: {toMillis: () => i + 1}}));
  const first = history(rows), second = history(rows, first.nextOffset);
  const third = history(rows, second.nextOffset);
  assert.equal(first.items.length, 100);
  assert.equal(second.items.length, 100);
  assert.equal(third.items.length, 5);
  assert.equal(third.nextOffset, null);
  assert.equal(new Set([...first.items, ...second.items, ...third.items].map(row => row.action)).size, 205);
  assert.deepEqual(history(rows, -100), first);
});
