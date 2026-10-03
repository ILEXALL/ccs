const {test} = require('node:test');
const assert = require('node:assert/strict');
const {planDocument} = require('../lib/account-deletion/plan');
const account = {uid: 'alice', username: 'alice_driver'};

test('deletes own content, relationship rows and private subcollections', () => {
  for (const [path, data] of [
    ['users/alice/legal_acceptances/v1', {}],
    ['global_chat/m1', {userId: 'alice', text: 'private'}],
    ['chats/group/messages/m1', {senderUid: 'alice'}],
    ['forum_topics/topic/replies/r1', {userId: 'alice'}],
    ['spots/s1', {addedByUid: 'alice'}],
    ['spot_reviews/r1', {userId: 'alice'}],
    ['friendships/f1', {userIds: ['alice', 'bob'], users: {alice: {name: 'Alice'}}}],
    ['telegram_login_sessions/s1', {telegram: {id: '123'}}],
  ]) {
    const owner = path.startsWith('telegram_') ? {uid: 'telegram_123'} : account;
    assert.equal(planDocument(path, data, owner).action, 'delete', path);
  }
});

test('preserves other members and transfers group ownership with aligned names/photos', () => {
  const data = {ownerUid: 'alice', memberIds: ['alice', 'bob', 'chris'],
    memberUsernames: ['alice_driver', 'b', 'c'], memberPhotoUrls: ['a.jpg', 'b.jpg', 'c.jpg'],
    moderatorIds: ['alice', 'bob'], lastSenderUid: 'alice', lastSenderUsername: 'alice_driver', lastMessage: 'erase me'};
  const result = planDocument('chats/group', data, account);
  assert.equal(result.action, 'replace');
  assert.equal(result.data.ownerUid, 'bob');
  assert.deepEqual(result.data.memberIds, ['bob', 'chris']);
  assert.deepEqual(result.data.memberUsernames, ['b', 'c']);
  assert.deepEqual(result.data.memberPhotoUrls, ['b.jpg', 'c.jpg']);
  assert.deepEqual(result.data.moderatorIds, ['bob']);
  assert.equal(result.data.lastMessage, '');
  assert.equal(data.lastMessage, 'erase me');
});

test('removes copied reply content even if author changed their username', () => {
  const result = planDocument('chats/group/messages/reply', {
    senderUid: 'bob', text: 'Keep this reply', replyToMessageId: 'old',
    replyToUsername: 'old_name', replyToText: 'Remove copied text', replyToPhotoUrl: 'photo.jpg',
  }, {...account, replyWasDeleted: true});
  assert.equal(result.data.text, 'Keep this reply');
  assert.equal(result.data.replyToText, '');
  assert.equal(result.data.replyToPhotoUrl, '');
});

test('removes reactions and read receipts without deleting another user message', () => {
  const result = planDocument('chats/group/messages/m2', {
    senderUid: 'bob', text: 'keep', reactions: {alice: 'heart', bob: 'like'}, readByUserIds: ['alice', 'bob'],
  }, account);
  assert.equal(result.action, 'replace');
  assert.deepEqual(result.data.reactions, {bob: 'like'});
  assert.deepEqual(result.data.readByUserIds, ['bob']);
});

test('does not substring match a different account or arbitrary message text', () => {
  assert.equal(planDocument('global_chat/m1', {userId: 'alice_other', text: 'alice'}, account).action, 'skip');
});

test('removes a notification with nested references rather than retaining its copied body', () => {
  assert.equal(planDocument('user_notifications/n1', {userId: 'bob', body: 'Alice said secret',
    data: {senderUid: 'alice'}}, account).action, 'delete');
});

test('removes shared references to deleted account media without erasing other users', () => {
  const result = planDocument('users/bob', {uid: 'bob', photoUrl: 'https://media.example/users/bob/avatar.jpg',
    media: 'https://media.example/users/alice/avatar.jpg'}, account);
  assert.equal(result.data.media, '');
  assert.equal(result.data.photoUrl, 'https://media.example/users/bob/avatar.jpg');
});

test('never scans or changes its own private queue and receipts', () => {
  assert.equal(planDocument('account_deletions/alice', {uid: 'alice'}, account).action, 'skip');
});

test('encoded Firebase Storage references are scrubbed without changing other accounts', () => {
  const result = planDocument('users/bob', {uid: 'bob',
    copiedPhoto: 'https://firebasestorage.googleapis.com/v0/b/bucket/o/users%2Falice%2Favatar.jpg?alt=media',
    photoUrl: 'https://media.example/users/alice_other/avatar.jpg'}, account);
  assert.equal(result.data.copiedPhoto, '');
  assert.equal(result.data.photoUrl, 'https://media.example/users/alice_other/avatar.jpg');
});

test('an empty group is deleted; a remaining member retains the group', () => {
  assert.equal(planDocument('chats/g', {memberIds: ['alice'], ownerUid: 'alice'}, account).action, 'delete');
  assert.equal(planDocument('chats/g', {memberIds: ['alice', 'bob'], ownerUid: 'alice'}, account).data.ownerUid, 'bob');
});

test('legacy reviewer UID is removed from content that belongs to another user', () => {
  const result = planDocument('forum_topics/t', {authorId: 'bob', reviewedBy: 'alice', title: 'keep'}, account);
  assert.equal(result.data.reviewedBy, '');
  assert.equal(result.data.title, 'keep');
});
