const test = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./support');

async function request(f, endpoint, uid, body, method = 'POST') {
  const res = { status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; }, setHeader() {} };
  await f.load(`../api/${endpoint}.js`)({ method,
    headers: uid ? { authorization: `Bearer ${uid}` } : {}, body }, res);
  return res;
}

test('[profiles] own profile sync awards once and ignores supplied user ID', async () => {
  const f = fixture({ 'users/tester': { photoUrl: 'avatar' }, 'users/other': {} });
  for (let i = 0; i < 2; i++) {
    assert.equal((await request(f, 'xp-sync', 'tester', {
      action: 'sync_me', userId: 'other', amount: 999999,
    })).code, 200);
  }
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 50);
  assert.equal(f.rows.has('xp_user_stats/other'), false);
});

test('[profiles] regular user cannot sync another profile', async () => {
  const f = fixture({ 'users/other': { photoUrl: 'avatar' } });
  assert.equal((await request(f, 'xp-sync', 'tester', {
    action: 'sync_user', userId: 'other',
  })).code, 403);
  assert.equal(f.rows.has('xp_user_stats/other'), false);
});

test('[spots] pending then approved spot awards author once; client amount ignored', async () => {
  const f = fixture({ 'spots/s': { addedByUid: 'tester', status: 'pending', photoUrl: 'photo' } });
  const body = { action: 'sync_spot', spotId: 's', amount: 999999 };
  assert.equal((await request(f, 'xp-sync', 'tester', body)).code, 200);
  assert.equal(f.rows.has('xp_user_stats/tester'), false);
  // Approval is seeded, not executed: moderator locking requires emulator/UI tests.
  f.rows.get('spots/s').status = 'approved';
  for (let i = 0; i < 2; i++) assert.equal((await request(f, 'xp-sync', 'tester', body)).code, 200);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 75);
});

test('[spots] unrelated user cannot synchronize someone else spot', async () => {
  const f = fixture({ 'spots/s': { addedByUid: 'owner', status: 'approved' } });
  assert.equal((await request(f, 'xp-sync', 'tester', { action: 'sync_spot', spotId: 's' })).code, 403);
});

test('[access] endpoints reject missing authentication and unsupported method', async () => {
  for (const endpoint of ['xp-sync', 'xp-leaderboard', 'moderation-action']) {
    const f = fixture();
    assert.equal((await request(f, endpoint, null, {})).code, 401);
    assert.equal((await request(f, endpoint, 'tester', {}, 'GET')).code, 405);
  }
});

test('[moderation] only staff can pin a forum topic', async () => {
  for (const role of ['user', 'moderator', 'admin']) {
    const f = fixture({ 'users/tester': { role }, 'forum_topics/t': { isPinned: false } });
    const res = await request(f, 'moderation-action', 'tester', {
      action: 'set_forum_topic_pinned', topicId: 't', pinned: true,
    });
    assert.equal(res.code, role === 'user' ? 403 : 200);
    assert.equal(f.rows.get('forum_topics/t').isPinned, role !== 'user');
  }
});

test('[chats] group owner can remove member and member metadata stays aligned', async () => {
  const f = fixture({ 'chats/c': { isGroup: true, ownerUid: 'tester',
    memberIds: ['tester', 'target', 'last'], memberUsernames: ['owner', 'target', 'last'],
    memberPhotoUrls: ['a', 'b', 'c'], moderatorIds: ['target'] } });
  const res = await request(f, 'moderation-action', 'tester', {
    action: 'remove_chat_member', chatId: 'c', targetUserId: 'target',
  });
  assert.equal(res.code, 200);
  const chat = f.rows.get('chats/c');
  assert.deepEqual(chat.memberIds, ['tester', 'last']);
  assert.deepEqual(chat.memberPhotoUrls, ['a', 'c']);
  assert.deepEqual(chat.moderatorIds, []);
});

test('[chats] ordinary member cannot remove another member', async () => {
  const f = fixture({ 'chats/c': { isGroup: true, ownerUid: 'owner',
    memberIds: ['owner', 'tester', 'target'] } });
  assert.equal((await request(f, 'moderation-action', 'tester', {
    action: 'remove_chat_member', chatId: 'c', targetUserId: 'target',
  })).code, 403);
  assert.deepEqual(f.rows.get('chats/c').memberIds, ['owner', 'tester', 'target']);
});
