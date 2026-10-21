const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {activeBan, banHistory} = require('../lib/ban-history');
const ts = n => ({toMillis: () => n});

test('expiry boundary removes stale banned flag from active list', () => {
  assert.equal(activeBan({banned: true, bannedUntil: ts(100)}, 99), true);
  assert.equal(activeBan({banned: true, bannedUntil: ts(100)}, 100), false);
  assert.equal(activeBan({banned: true}, 100), true);
  assert.equal(activeBan({banned: false}, 100), false);
});

test('legacy snapshot and logged ban count once; repeat bans remain distinct', () => {
  const logs = [
    {action: 'user_banned', createdAt: ts(10), bannedUntil: ts(20), reason: 'First'},
    {action: 'user_banned', createdAt: ts(30), bannedUntil: ts(40), reason: 'Second'},
  ];
  const history = banHistory({bannedAt: ts(30), bannedUntil: ts(40), banned: true}, logs);
  assert.equal(history.length, 2);
  assert.equal(history[0].reason, 'Second');
  assert.equal(history[1].expiresAt, 20);
});

test('old profile-only bans retain dates, reason and manual removal', () => {
  assert.deepEqual(banHistory({banned: false, bannedAt: ts(10), bannedUntil: ts(30),
    banReason: 'Spam', unbannedAt: ts(20)}, []),
    [{bannedAt: 10, expiresAt: 30, reason: 'Spam', liftedAt: 20, bannedByUid: '', bannedBy: ''}]);
});

test('each ban keeps its own issuer; legacy profile only fills the matching ban', () => {
  const history = banHistory({bannedAt: ts(30), bannedUntil: ts(40),
    bannedByUid: 'mod2', bannedBy: 'second_mod'}, [
    {action: 'user_banned', createdAt: ts(10), bannedUntil: ts(20), actorUid: 'mod1', actorUsername: 'first_mod'},
    {action: 'user_banned', createdAt: ts(30), bannedUntil: ts(40), actorUid: 'mod2'},
  ]);
  assert.equal(history[0].bannedBy, 'second_mod');
  assert.equal(history[1].bannedBy, 'first_mod');
  assert.equal(history[1].bannedByUid, 'mod1');
  assert.equal(banHistory({}, [{action: 'user_banned', createdAt: ts(1)}])[0].bannedBy, '');
});

test('unban logs attach to the right ban, including after a later reban', () => {
  const history = banHistory({}, [
    {action: 'user_banned', createdAt: ts(10), bannedUntil: ts(40)},
    {action: 'user_unbanned', banStartedAt: ts(10), createdAt: ts(20)},
    {action: 'user_banned', createdAt: ts(30), bannedUntil: ts(60)},
  ]);
  assert.equal(history[0].liftedAt, null);
  assert.equal(history[1].liftedAt, 20);
});

function service({role = 'admin', country = 'LV'} = {}) {
  const writes = [];
  const actor = {uid: 'staff', user: {role}};
  const target = {role: 'user', username: 'driver', country, banned: true,
    bannedAt: ts(10), bannedUntil: ts(20), banReason: 'Spam', deviceIds: ['device123']};
  const snap = (id, data, ref) => ({id, exists: !!data, data: () => data, ref});
  const db = {collection: name => ({
    doc: (id = 'new-log') => ({name, id, get: async () => snap(id, target)}),
    where: () => ({name, query: true}),
    orderBy: () => {
      const q = {orderBy: () => q, limit: () => q,
        get: async () => ({size: 1, docs: [snap('driver', target)]})};
      return q;
    },
  })};
  const tx = {
    get: async ref => ref.query ? {docs: []} : snap(ref.id,
      ref.id === 'staff' ? actor.user : ref.name === 'device_bans' ?
        {sourceUserUid: 'someone_else'} : target, ref),
    set: (ref, data) => writes.push({ref, data}),
    update: (ref, data) => writes.push({ref, data}),
    create: (ref, data) => writes.push({ref, data}),
  };
  db.runTransaction = fn => fn(tx);
  const module = {exports: {}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../lib/user-ban'), 'utf8'), {
    module, Date, require: path => {
      if (path === './firebase-admin') return {db, admin: {firestore: {
        FieldPath: {documentId: () => '__name__'}, FieldValue: {serverTimestamp: () => ts(15)},
      }}};
      if (path === './regional-moderation') return {canModerateCountry: (user, code) =>
        user?.role === 'admin' || (user?.role === 'moderator' && code === 'LV')};
      if (path === './private-groups') return {countryCode: c => c};
      return require('../lib/ban-history');
    },
  });
  return {...module.exports, actor, writes};
}

test('unban preserves legacy history and does not clear another user device ban', async () => {
  const s = service();
  await s.unbanUserAction({actor: s.actor, body: {targetUserId: 'driver'}});
  assert.equal(s.writes.filter(w => w.data.action === 'user_banned').length, 1);
  assert.equal(s.writes.filter(w => w.data.action === 'user_unbanned').length, 1);
  assert.equal(s.writes.some(w => w.ref.name === 'device_bans'), false);
  assert.equal(s.writes.find(w => w.ref.name === 'users').data.banned, false);
});

test('moderator cannot unban or see bans outside assigned country', async () => {
  const s = service({role: 'moderator', country: 'RU'});
  await assert.rejects(s.unbanUserAction({actor: s.actor, body: {targetUserId: 'driver'}}), /permission/);
  const page = await s.listBansAction({actor: s.actor, body: {}});
  assert.equal(page.entries.length, 0);
  assert.equal(s.writes.length, 0);
});

test('ordinary users cannot access ban history', async () => {
  const s = service({role: 'user'});
  await assert.rejects(s.listBansAction({actor: s.actor, body: {}}), /Staff access/);
});
