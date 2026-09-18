const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
const {weekKeyFor} = require('../lib/xp/xp-engine');

async function request(f, body = {}) {
  const response = {status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;}, setHeader() {}};
  await f.load('../handlers/xp-leaderboard.js')({method: 'POST',
    headers: {authorization: 'Bearer tester'}, body}, response);
  return response;
}
function populate(f, count) {
  const weekKey = weekKeyFor(new Date());
  for (let i = 0; i < count; i++) {
    const userId = `u${String(i).padStart(4, '0')}`;
    f.rows.set(`users/${userId}`, {username: `Driver_${i}`});
    f.rows.set(`xp_user_stats/${userId}`, {xpTotal: 10000 - i, level: 5,
      weeklyXp: 3000 - i, weeklyXpWeek: weekKey});
    f.rows.set(`xp_user_weeks/${userId}_${weekKey}`, {userId, weekKey, confirmedXp: 3000 - i});
  }
}
for (const period of ['all_time', 'weekly']) {
  test(`${period}: pages default to ten and preserve ranks through the last page`, async () => {
    const f = fixture(); populate(f, 25);
    const all = [];
    let cursor;
    for (const size of [10, 10, 5]) {
      const response = await request(f, {period, cursor});
      assert.equal(response.code, 200);
      const result = response.body.result;
      assert.equal(result.entries.length, size);
      all.push(...result.entries);
      cursor = result.nextCursor;
      assert.equal(result.hasMore, all.length < 25);
    }
    assert.equal(cursor, null);
    const userReads = f.reads.filter(read => read.keys.every(key => key.startsWith('users/')));
    assert.ok(userReads.every(read => read.keys.length <= 10));
    // 25 displayed users plus one lookahead for each non-final page.
    assert.equal(userReads.reduce((sum, read) => sum + read.keys.length, 0), 27);
    assert.deepEqual(all.map(row => row.rank), Array.from({length: 25}, (_, i) => i + 1));
    assert.equal(new Set(all.map(row => row.userId)).size, 25);
  });
  test(`${period}: hidden, inactive and blocked users do not consume page slots`, async () => {
    const f = fixture(); populate(f, 35);
    for (let i = 0; i < 15; i++) {
      const user = f.rows.get(`users/u${String(i).padStart(4, '0')}`);
      if (i % 3 === 0) user.publicProfile = false;
      if (i % 3 === 1) user.banned = true;
      if (i % 3 === 2) user.deleted = true;
    }
    f.rows.get('xp_user_stats/u0015').xpBlocked = true;
    const response = await request(f, {period});
    const entries = response.body.result.entries;
    assert.equal(entries.length, 10);
    assert.equal(entries[0].userId, 'u0016');
    assert.equal(entries[0].rank, 1);
  });
  test(`${period}: search reaches legacy nicknames beyond loaded pages, with real ranks`, async () => {
    const f = fixture(); populate(f, 125);
    f.rows.get('users/u0124').username = 'Late_Driver';
    const response = await request(f, {period, search: ' @LATE_ '});
    assert.equal(response.code, 200);
    const result = response.body.result;
    assert.equal(result.entries.length, 1);
    assert.equal(result.entries[0].userId, 'u0124');
    assert.equal(result.entries[0].rank, 125);
    assert.equal(result.hasMore, false);
    f.rows.get('users/u0124').settings = {publicProfile: false};
    assert.equal((await request(f, {period, search: 'Late_'})).body.result.entries.length, 0);
  });
  test(`${period}: search pages do not duplicate results and cursor context is validated`, async () => {
    const f = fixture(); populate(f, 31);
    const first = (await request(f, {period, search: 'driver_'})).body.result;
    const second = (await request(f, {period, search: 'driver_', cursor: first.nextCursor})).body.result;
    assert.equal(second.entries[0].rank, 11);
    assert.equal(new Set([...first.entries, ...second.entries].map(row => row.userId)).size, 20);
    for (const changes of [{search: 'other'}, {period: period === 'weekly' ? 'all_time' : 'weekly'},
      {cursor: {...first.nextCursor, weekKey: '2000-01-01'}},
      {cursor: {...first.nextCursor, afterId: 'invalid/path'}}]) {
      assert.equal((await request(f, {period, search: 'driver_', cursor: first.nextCursor, ...changes})).code, 409);
    }
  });
  test(`${period}: an anchor made private cannot be used to continue`, async () => {
    const f = fixture(); populate(f, 25);
    const cursor = (await request(f, {period})).body.result.nextCursor;
    f.rows.get(`users/${cursor.afterId}`).publicProfile = false;
    assert.equal((await request(f, {period, cursor})).code, 409);
  });
  test(`${period}: exactly ten results have no extra page`, async () => {
    const f = fixture(); populate(f, 10);
    const result = (await request(f, {period})).body.result;
    assert.equal(result.entries.length, 10);
    assert.equal(result.hasMore, false);
    assert.equal(result.nextCursor, null);
  });
}
test('changed or deleted all-time page anchor requires refresh', async () => {
  const f = fixture(); populate(f, 21);
  const cursor = (await request(f)).body.result.nextCursor;
  f.rows.get(`xp_user_stats/${cursor.afterId}`).xpTotal++;
  assert.equal((await request(f, {cursor})).code, 409);
  f.rows.delete(`xp_user_stats/${cursor.afterId}`);
  assert.equal((await request(f, {cursor})).code, 409);
});
