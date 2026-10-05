const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const admin = process.env.CCS_TEST_DEPENDENCIES
  ? require(require.resolve('firebase-admin', {paths: [process.env.CCS_TEST_DEPENDENCIES]}))
  : require('firebase-admin');
const {processDeletion} = require('../lib/account-deletion/worker');
const {collectionPager} = require('../lib/account-deletion/list-page');
const {runDeletionQueue} = require('../lib/account-deletion/queue');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw new Error('Only the local test emulator is permitted');
const projectId = 'demo-ccs-tests';
const app = admin.initializeApp({projectId}, 'deletion-tests');
const db = app.firestore();
const listPage = collectionPager({db});
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {host: '127.0.0.1', port: 18080,
    rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env?.cleanup(); await app.delete(); });
async function seed(rows) {
  for (const [key, value] of Object.entries(rows)) await db.doc(key).set(value);
}
const auth = () => ({updateUser: async () => {}, revokeRefreshTokens: async () => {}, deleteUser: async () => {}});

test('restricted queue processes only its account and leaves public health and metadata alone', async () => {
  const {deletionScope} = require('../lib/account-deletion/scope');
  await seed({
    'account_deletions/alice': {status: 'queued'},
    'account_deletions/bob': {status: 'queued'},
    'account_deletions/old': {status: 'complete', completedAt: 1},
    'account_deletion_receipts/old': {status: 'complete', completedAt: 1},
    'account_deletion_scheduler/round-robin': {lastRunOk: false, sentinel: 'unchanged'},
  });
  const seen = [];
  const result = await runDeletionQueue({db, onlyUid: 'alice', runJob: async ref => {
    seen.push(ref.id); await ref.update({status: 'complete'});
  }});
  assert.deepEqual(seen, ['alice']);
  assert.equal(result.pending, false);
  assert.equal((await db.doc('account_deletions/bob').get()).data().status, 'queued');
  assert.equal((await db.doc('account_deletions/old').get()).exists, true);
  assert.equal((await db.doc('account_deletion_receipts/old').get()).exists, true);
  assert.deepEqual((await db.doc('account_deletion_scheduler/round-robin').get()).data(), {lastRunOk: false, sentinel: 'unchanged'});
  const scope = deletionScope({ACCOUNT_DELETION_TEST_UID: 'alice'});
  assert.equal((await db.doc(`account_deletion_scheduler/${scope.stateId}`).get()).data().lastRunOk, true);
  const empty = await runDeletionQueue({db, onlyUid: 'alice', runJob: async () => assert.fail('completed test must not run')});
  assert.equal(empty.attempted, 0);
});

test('queue rotates past failed and unfinished jobs and records scheduler health', async () => {
  for (const id of ['a', 'b', 'c', 'd', 'e', 'f']) {
    await db.doc(`account_deletions/${id}`).set({status: 'queued'});
  }
  const calls = [];
  const runJob = async ref => {calls.push(ref.id); if (ref.id === 'a') throw new Error('test storage failure');};
  const first = await runDeletionQueue({db, runJob});
  assert.equal(first.ok, false);
  assert.equal(first.attempted, 5);
  assert.equal(first.pending, true);
  await runDeletionQueue({db, runJob});
  assert.deepEqual(calls, ['a', 'b', 'c', 'd', 'e', 'f']);
  const state = (await db.doc('account_deletion_scheduler/round-robin').get()).data();
  assert.equal(state.after, 'f');
  assert.equal(state.lastRunOk, true);
  assert.equal(state.leaseUntil, 0);
  assert.ok(state.lastFinishedAt >= state.lastStartedAt);
});

test('overlapping scheduler runs do not process the same queue', async () => {
  await db.doc('account_deletion_scheduler/round-robin').set({leaseUntil: Date.now() + 60000});
  const result = await runDeletionQueue({db, runJob: async () => assert.fail('duplicate worker')});
  assert.equal(result.busy, true);
});

test('one waiting job receives the available budget and five jobs share it', async () => {
  await seed({'account_deletions/a': {status: 'queued'}});
  const budgets = [];
  await runDeletionQueue({db, now: () => 1000, runJob: async (_, budget) => budgets.push(budget)});
  assert.deepEqual(budgets, [35000]);
  for (const id of ['b', 'c', 'd', 'e']) await db.doc(`account_deletions/${id}`).set({status: 'queued'});
  await db.doc('account_deletion_scheduler/round-robin').update({after: ''});
  let time = 2000;
  budgets.length = 0;
  await runDeletionQueue({db, now: () => time, runJob: async (_, budget) => {budgets.push(budget); time += budget;}});
  assert.deepEqual(budgets, [7000, 7000, 7000, 7000, 7000]);
});

test('a failed batch commits neither deletions nor its cursor and resumes safely', async t => {
  const {createHash} = require('node:crypto');
  const ref = db.doc('account_deletions/alice');
  const task = ref.collection('tasks').doc(createHash('sha256').update('global_chat').digest('hex'));
  const paths = Array.from({length: 12}, (_, i) => `global_chat/m${i}`);
  await seed({[ref.path]: {status: 'processing', initialized: true, receiptHash: 'receipt'},
    [task.path]: {kind: 'collection', path: 'global_chat', pendingPaths: paths, lastPage: true}});
  for (const [i, path] of paths.entries()) await db.doc(path).set({userId: i % 2 ? 'bob' : 'alice'});
  const original = db.runTransaction.bind(db);
  const mock = t.mock.method(db, 'runTransaction', (callback, ...options) => original(async tx => {
    const update = tx.update.bind(tx);
    tx.update = (target, ...args) => {
      if (target.path === task.path) throw new Error('injected batch failure');
      return update(target, ...args);
    };
    return callback(tx);
  }, ...options));
  await assert.rejects(processDeletion({db, listPage, jobRef: ref, auth: auth(), media: {}}), /injected batch failure/);
  mock.mock.restore();
  assert.equal((await db.collection('global_chat').get()).size, 12);
  assert.deepEqual((await task.get()).data().pendingPaths, paths);
  assert.equal((await ref.get()).data().leaseUntil, 0);
  await processDeletion({db, listPage, jobRef: ref, auth: auth(), media: {}, budgetMs: 100000});
  assert.equal((await ref.get()).data().status, 'complete');
  const survivors = await db.collection('global_chat').get();
  assert.equal(survivors.size, 6);
  assert.ok(survivors.docs.every(doc => doc.data().userId === 'bob'));
});

test('completed UID tombstones and expired anonymous receipts are eventually removed', async () => {
  const now = Date.now();
  await seed({
    'account_deletions/old': {status: 'complete', completedAt: now - 3600001},
    'account_deletions/recent': {status: 'complete', completedAt: now - 1000},
    'account_deletion_receipts/old': {status: 'complete', completedAt: now - 31 * 86400000},
    'account_deletion_receipts/recent': {status: 'complete', completedAt: now},
    'account_deletion_scheduler/round-robin': {after: 'old'},
  });
  await runDeletionQueue({db, now: () => now, runJob: async () => assert.fail('no pending work')});
  assert.equal((await db.doc('account_deletions/old').get()).exists, false);
  assert.equal((await db.doc('account_deletions/recent').get()).exists, true);
  assert.equal((await db.doc('account_deletion_receipts/old').get()).exists, false);
  assert.equal((await db.doc('account_deletion_receipts/recent').get()).exists, true);
  assert.equal((await db.doc('account_deletion_scheduler/round-robin').get()).data().after, '');
});

test('deleted containers leave no orphan descendants, including missing intermediate documents', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({
    [ref.path]: {status: 'queued', receiptHash: 'receipt'},
    'users/alice': {deleted: true},
    'forum_topics/mine': {authorId: 'alice'},
    'forum_topics/mine/replies/bob': {userId: 'bob', text: 'reply'},
    'forum_topics/mine/replies/missing/reactions/bob': {value: 'like'},
    'chats/empty': {memberIds: ['alice'], ownerUid: 'alice'},
    'chats/empty/messages/system': {text: 'old personal content'},
    'forum_topics/other': {authorId: 'bob'},
    'forum_topics/other/replies/bob': {userId: 'bob', text: 'keep'},
  });
  let calls = 0;
  while ((await ref.get()).data().status !== 'complete' && calls++ < 100) {
    await processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 3,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await ref.get()).data().status, 'complete');
  for (const path of ['forum_topics/mine/replies/bob', 'forum_topics/mine/replies/missing/reactions/bob',
    'chats/empty', 'chats/empty/messages/system']) assert.equal((await db.doc(path).get()).exists, false, path);
  assert.equal((await db.doc('forum_topics/other/replies/bob').get()).data().text, 'keep');
});

test('deletion removes copied spot notifications and group links scanned before the spot', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({
    [ref.path]: {status: 'queued', receiptHash: 'receipt'},
    'spots/mine': {addedByUid: 'alice', name: 'personal name'},
    'spots/other': {addedByUid: 'bob'},
    'user_notifications/copied': {userId: 'bob', body: 'personal name', data: {spotId: 'mine'}},
    'chats/shared/spot_links/mine': {spotId: 'mine', spotName: 'personal name'},
    'spot_reviews/review': {userId: 'bob', spotId: 'mine', spotName: 'personal name'},
    'user_notifications/keep': {userId: 'bob', data: {spotId: 'other'}},
  });
  let calls = 0;
  while ((await ref.get()).data().status !== 'complete' && calls++ < 100) {
    await processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 2,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await ref.get()).data().status, 'complete');
  for (const path of ['user_notifications/copied', 'chats/shared/spot_links/mine', 'spot_reviews/review']) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await db.doc('user_notifications/keep').get()).exists, true);
  assert.equal((await ref.collection('content_checks').get()).empty, true);
});

test('media cleanup waits for previously issued upload URLs to expire', async () => {
  const ref = db.doc('account_deletions/alice');
  const requestedAt = Date.now();
  await seed({[ref.path]: {status: 'queued', requestedAt, receiptHash: 'receipt'}});
  await processDeletion({db, listPage, jobRef: ref, now: () => requestedAt + 300000,
    auth: {updateUser: async () => assert.fail('Worker started before upload expiry')},
    media: {deletePrefixPage: async () => assert.fail('Media deleted too early')}});
  assert.equal((await ref.get()).data().status, 'queued');
  assert.equal((await ref.get()).data().initialized, undefined);
});

test('large scan pages resume mid-page and discover orphan descendants without skipping other users', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {status: 'queued', receiptHash: 'receipt'}});
  const writer = db.bulkWriter();
  for (let i = 0; i < 130; i++) {
    const id = `m${String(i).padStart(3, '0')}`;
    writer.set(db.doc(`global_chat/${id}`), {userId: i % 2 ? 'bob' : 'alice', text: id});
  }
  writer.set(db.doc('global_chat/m065/reactions/alice'), {uid: 'alice'});
  writer.set(db.doc('global_chat/m065/reactions/bob'), {uid: 'bob'});
  writer.set(db.doc('global_chat/missing/reactions/alice'), {uid: 'alice'});
  await writer.close();
  let calls = 0;
  while ((await ref.get()).data().status !== 'complete' && calls++ < 30) {
    await processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 31,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await ref.get()).data().status, 'complete');
  const remaining = await db.collection('global_chat').get();
  assert.equal(remaining.size, 65);
  assert.ok(remaining.docs.every(doc => doc.data().userId === 'bob' && doc.data().text === doc.id));
  assert.equal((await db.doc('global_chat/m065/reactions/alice').get()).exists, false);
  assert.equal((await db.doc('global_chat/missing/reactions/alice').get()).exists, false);
  assert.equal((await db.doc('global_chat/m065/reactions/bob').get()).exists, true);
});

test('indexed history cleanup paginates owned rows, removes actor copies, and does not scan unrelated history', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {status: 'queued', receiptHash: 'receipt'},
    'user_notifications/actor': {userId: 'bob', actorUserId: 'alice'},
    'user_notifications/nested': {userId: 'bob', data: {senderUid: 'alice'}},
    'user_notifications/keep': {userId: 'bob', actorUserId: 'carol'},
    'push_deliveries/keep': {userId: 'bob'}});
  for (let i = 0; i < 57; i++) {
    await db.doc(`user_notifications/m${i}`).set({userId: 'alice'});
    await db.doc(`push_deliveries/m${i}`).set({userId: 'alice'});
  }
  const guardedPager = (path, token) => {
    assert.ok(!['user_notifications', 'push_deliveries'].includes(path), 'large collections must use indexes');
    return listPage(path, token);
  };
  let calls = 0;
  while ((await ref.get()).data().status !== 'complete' && calls++ < 100) {
    await processDeletion({db, listPage: guardedPager, jobRef: ref, auth: auth(), maxDocuments: 7,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await ref.get()).data().status, 'complete');
  assert.deepEqual((await db.collection('user_notifications').get()).docs.map(doc => doc.id), ['keep']);
  assert.deepEqual((await db.collection('push_deliveries').get()).docs.map(doc => doc.id), ['keep']);
});

test('old jobs with hashed content references retain the safe notification fallback', async () => {
  const {createHash} = require('node:crypto');
  const ref = db.doc('account_deletions/alice');
  const hash = path => createHash('sha256').update(path).digest('hex');
  await seed({[ref.path]: {initialized: true, status: 'processing', receiptHash: 'receipt'},
    [`${ref.path}/tasks/${hash('user_notifications')}`]: {kind: 'collection', path: 'user_notifications'},
    [`${ref.path}/references/${hash('spots/gone')}`]: {deleted: true},
    'user_notifications/copy': {userId: 'bob', data: {spotId: 'gone'}},
    'user_notifications/keep': {userId: 'bob', data: {spotId: 'keep'}}});
  await processDeletion({db, listPage, jobRef: ref, auth: auth(), budgetMs: 100000, media: {}});
  assert.equal((await db.doc('user_notifications/copy').get()).exists, false);
  assert.equal((await db.doc('user_notifications/keep').get()).exists, true);
  assert.equal((await ref.get()).data().status, 'complete');
});

test('indexed chat preview cleanup checks both chat and message IDs', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {status: 'queued', receiptHash: 'receipt'},
    'chats/one/messages/same': {senderUid: 'alice', text: 'erase'},
    'chats/two/messages/same': {senderUid: 'bob', text: 'keep'},
    'user_notifications/copied': {userId: 'bob', body: 'erase', data: {chatId: 'one', messageId: 'same'}},
    'user_notifications/keep': {userId: 'bob', body: 'keep', data: {chatId: 'two', messageId: 'same'}}});
  await processDeletion({db, listPage, jobRef: ref, auth: auth(), budgetMs: 100000,
    media: {deletePrefixPage: async () => true}});
  assert.equal((await ref.get()).data().status, 'complete');
  assert.equal((await db.doc('user_notifications/copied').get()).exists, false);
  assert.equal((await db.doc('user_notifications/keep').get()).data().body, 'keep');
});

test('removes content and orphan descendants, scrubs old reply previews, keeps other members', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({
    [ref.path]: {status: 'queued', username: 'new_alice', receiptHash: 'receipt'},
    'account_deletion_receipts/receipt': {status: 'processing'},
    'users/alice': {uid: 'alice', deleted: true, name: 'Alice', garage: [{photoUrl: 'private'}]},
    'users/alice/legal_acceptances/v1': {termsVersion: 'v1'},
    'users/alice/private/account': {email: 'synthetic@example.invalid', fcmTokens: ['synthetic-token']},
    'users/bob': {uid: 'bob', name: 'Bob'},
    'global_chat/mine': {userId: 'alice', text: 'erase', photoUrl: 'erase.jpg'},
    'global_chat/reply': {userId: 'bob', text: 'keep', replyToMessageId: 'mine', replyToUsername: 'old_alice', replyToText: 'erase', replyToPhotoUrl: 'erase.jpg'},
    'chats/group': {isGroup: true, ownerUid: 'alice', memberIds: ['alice', 'bob'], memberUsernames: ['old_alice', 'bob'], memberPhotoUrls: ['a', 'b'], lastSenderUid: 'alice', lastMessage: 'erase'},
    'chats/group/messages/mine': {senderUid: 'alice', text: 'erase'},
    'chats/group/messages/other': {senderUid: 'bob', text: 'keep', readByUserIds: ['alice', 'bob'], reactions: {alice: 'like'}},
    'chats/orphan/messages/mine': {senderUid: 'alice', text: 'erase'},
    'spots/spot1': {addedByUid: 'alice', name: 'erase'},
    'spot_reviews/other': {userId: 'bob', text: 'keep'},
  });
  const deletedPrefixes = [];
  let authDeleted = false;
  await processDeletion({db, listPage, jobRef: ref, budgetMs: 100000, auth: {...auth(), deleteUser: async uid => {
    assert.equal(uid, 'alice');
    assert.equal((await db.doc('global_chat/mine').get()).exists, false);
    authDeleted = true;
  }}, media: {deletePrefixPage: async prefix => {deletedPrefixes.push(prefix); return true;}}});
  assert.equal((await ref.get()).data().status, 'complete');
  assert.equal(authDeleted, true);
  for (const key of ['users/alice', 'users/alice/legal_acceptances/v1', 'users/alice/private/account', 'global_chat/mine', 'chats/orphan/messages/mine', 'spots/spot1']) {
    assert.equal((await db.doc(key).get()).exists, false, key);
  }
  assert.equal((await db.doc('users/bob').get()).data().name, 'Bob');
  assert.equal((await db.doc('spot_reviews/other').get()).data().text, 'keep');
  const reply = (await db.doc('global_chat/reply').get()).data();
  assert.equal(reply.text, 'keep'); assert.equal(reply.replyToText, ''); assert.equal(reply.replyToPhotoUrl, '');
  const group = (await db.doc('chats/group').get()).data();
  assert.equal(group.ownerUid, 'bob'); assert.deepEqual(group.memberIds, ['bob']);
  assert.deepEqual(group.memberPhotoUrls, ['b']); assert.equal(group.lastMessage, '');
  assert.deepEqual(new Set(deletedPrefixes), new Set(['users/alice/', 'garage/alice/', 'spots/spot1/']));
  assert.equal((await db.doc('account_deletion_receipts/receipt').get()).data().status, 'complete');
});

test('a storage failure does not claim completion or delete auth; retry resumes safely', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {status: 'queued', receiptHash: 'receipt'}, 'users/alice': {deleted: true}});
  let deleted = 0;
  const accountAuth = {...auth(), deleteUser: async () => {deleted++;}};
  await assert.rejects(processDeletion({db, listPage, jobRef: ref, auth: accountAuth,
    media: {deletePrefixPage: async () => {throw new Error('R2 unavailable');}}}), /R2 unavailable/);
  assert.notEqual((await ref.get()).data().status, 'complete');
  assert.equal(deleted, 0);
  assert.equal((await ref.get()).data().leaseUntil, 0);
  await processDeletion({db, listPage, jobRef: ref, auth: accountAuth, budgetMs: 100000, media: {deletePrefixPage: async () => true}});
  assert.equal((await ref.get()).data().status, 'complete');
  assert.equal(deleted, 1);
});

test('an active worker lease prevents duplicate work', async () => {
  const ref = db.doc('account_deletions/alice');
  await ref.set({status: 'processing', leaseUntil: Date.now() + 60000});
  await processDeletion({db, listPage, jobRef: ref, auth: {updateUser: async () => assert.fail('must not run')}, media: {}});
});

test('empty deleted-source index clears only temporary deferred checks in bounded batches', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {initialized: true, indexedReferences: true, status: 'processing', receiptHash: 'receipt'},
    'global_chat/other': {userId: 'bob', text: 'keep', replyToText: 'keep'},
    [`${ref.path}/reply_checks/a`]: {path: 'global_chat/other'},
    [`${ref.path}/reply_checks/b`]: {path: 'global_chat/other'},
    [`${ref.path}/content_checks/a`]: {path: 'global_chat/other'}});
  await processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 2, media: {}});
  assert.equal((await ref.collection('reply_checks').get()).empty, true);
  assert.equal((await ref.collection('content_checks').get()).size, 1);
  assert.equal((await ref.get()).data().status, 'processing');
  await processDeletion({db, listPage, jobRef: ref, auth: auth(), media: {}});
  assert.equal((await ref.get()).data().status, 'complete');
  assert.deepEqual((await db.doc('global_chat/other').get()).data(), {userId: 'bob', text: 'keep', replyToText: 'keep'});
});

test('queued deletion immediately blocks old client tokens and queue access', async () => {
  await seed({'users/alice': {uid: 'alice'}, 'users/bob': {uid: 'bob'}, 'account_deletions/alice': {status: 'queued'}});
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  await assertFails(getDoc(doc(alice, 'users/bob')));
  await assertFails(setDoc(doc(alice, 'global_chat/new'), {userId: 'alice', text: 'after deletion'}));
  await assertFails(getDoc(doc(bob, 'account_deletions/alice')));
  await assertFails(setDoc(doc(bob, 'account_deletions/bob'), {status: 'queued'}));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'account_deletion_receipts/receipt')));
  await assertSucceeds(getDoc(doc(bob, 'users/bob')));
});

test('small worker budgets resume across page boundaries without skipping documents', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({[ref.path]: {status: 'queued', receiptHash: 'receipt'}, 'users/alice': {deleted: true}});
  for (let i = 0; i < 57; i++) await db.doc(`global_chat/message_${String(i).padStart(3, '0')}`).set({userId: i % 2 ? 'bob' : 'alice', text: `message ${i}`});
  let calls = 0;
  while ((await ref.get()).data().status !== 'complete' && calls++ < 80) {
    await processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 7,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await ref.get()).data().status, 'complete');
  const remaining = await db.collection('global_chat').get();
  assert.equal(remaining.size, 28);
  assert.ok(remaining.docs.every(doc => doc.data().userId === 'bob'));
});

test('reply index resumes after source deletion and checks the current reply target', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({
    [ref.path]: {status: 'queued', username: 'new_alice', receiptHash: 'receipt'},
    'users/alice': {deleted: true},
    'global_chat/a_preview': {userId: 'bob', text: 'keep', replyToMessageId: 'z_mine', replyToUsername: 'old_alice', replyToText: 'erase'},
    'global_chat/b_retarget': {userId: 'bob', text: 'keep', replyToMessageId: 'z_mine', replyToUsername: 'old_alice', replyToText: 'erase'},
    'global_chat/z_mine': {userId: 'alice', text: 'erase'},
    'global_chat/zz_other': {userId: 'bob', text: 'other'},
  });
  const advance = () => processDeletion({db, listPage, jobRef: ref, auth: auth(), maxDocuments: 1,
    media: {deletePrefixPage: async () => true}});
  let calls = 0;
  while ((await db.doc('global_chat/z_mine').get()).exists && calls++ < 100) await advance();
  assert.equal((await db.doc('global_chat/z_mine').get()).exists, false);
  assert.equal((await ref.collection('reply_checks').get()).size, 2);
  // A different user can change a reply between the scan and its deferred check.
  await db.doc('global_chat/b_retarget').update({replyToMessageId: 'zz_other', replyToUsername: 'bob', replyToText: 'other'});
  while ((await ref.get()).data().status !== 'complete' && calls++ < 150) await advance();
  assert.equal((await ref.get()).data().status, 'complete');
  const preview = (await db.doc('global_chat/a_preview').get()).data();
  assert.equal(preview.text, 'keep');
  assert.equal(preview.replyToText, '');
  assert.equal((await db.doc('global_chat/b_retarget').get()).data().replyToText, 'other');
  assert.equal((await ref.collection('reply_checks').get()).empty, true);
  assert.equal((await ref.collection('references').get()).empty, true);
});

test('request derives account from fresh authenticated token and receipt exposes only status', async () => {
  const {createHash} = require('node:crypto');
  const module = {exports: {}};
  let token = {uid: 'alice', auth_time: Math.floor(Date.now() / 1000)};
  const calls = [];
  const context = {
    module, Buffer, Date, console, process: {env: {ACCOUNT_DELETION_ENABLED: 'true', CRON_SECRET: 'local-test-only'}},
    require: name => {
      if (name === 'node:crypto') return require(name);
      if (name.endsWith('/scope')) return require('../lib/account-deletion/scope');
      if (name.endsWith('/firebase-admin')) return {db, admin: {storage: () => ({}), firestore: admin.firestore, auth: () => ({
        verifyIdToken: async (_, revoked) => {assert.equal(revoked, true); return token;},
        updateUser: async (uid, fields) => {calls.push(['disable', uid, fields.disabled]);},
        revokeRefreshTokens: async uid => {calls.push(['revoke', uid]);},
      })}};
      if (name.endsWith('/storage')) return {storageAdapter: () => ({})};
      if (name.endsWith('/worker')) return {};
      if (name.endsWith('/list-page')) return {};
      if (name.endsWith('/queue')) return {};
      throw Error('Unexpected dependency');
    },
  };
  // Run in this realm so Firestore receives native plain objects.
  new Function(...Object.keys(context), fs.readFileSync(path.resolve(__dirname, '../handlers/account-deletion.js'), 'utf8'))(...Object.values(context));
  async function request(body) {
    const result = {code: 200, setHeader() {}, status(code) {this.code = code; return this;}, json(data) {this.data = data; return this;}};
    await module.exports({method: 'POST', headers: {authorization: 'Bearer test'}, body}, result);
    return result;
  }
  const receipt = 'a'.repeat(64);
  await seed({'users/alice': {username: 'alice'}, 'users/bob': {username: 'bob'}});
  assert.equal((await request({receipt, confirmation: 'DELETE'})).code, 503);
  await db.doc('account_deletion_scheduler/round-robin').set({lastFinishedAt: Date.now(), lastRunOk: true});
  assert.equal((await request({receipt, confirmation: 'no'})).code, 400);
  token.auth_time -= 1000;
  assert.equal((await request({receipt, confirmation: 'DELETE'})).code, 401);
  token.auth_time += 1000;
  assert.equal((await request({receipt, confirmation: 'DELETE', uid: 'bob'})).code, 202);
  assert.equal((await db.doc('account_deletions/alice').get()).exists, true);
  assert.equal((await db.doc('account_deletions/bob').get()).exists, false);
  assert.deepEqual(calls.map(call => call.slice(0, 2)), [['disable', 'alice'], ['revoke', 'alice']]);
  const status = await request({action: 'status', receipt});
  assert.equal(status.data.status, 'processing');
  assert.deepEqual(Object.keys(status.data), ['status']);
  assert.equal((await db.doc(`account_deletion_receipts/${createHash('sha256').update(receipt).digest('hex')}`).get()).exists, true);
  context.process.env.ACCOUNT_DELETION_ENABLED = 'false';
  context.process.env.ACCOUNT_DELETION_TEST_UID = 'bob';
  assert.equal((await request({receipt, confirmation: 'DELETE', uid: 'bob'})).code, 503);
  context.process.env.ACCOUNT_DELETION_TEST_UID = 'alice';
  assert.equal((await request({receipt, confirmation: 'DELETE'})).code, 503);
  const {deletionScope} = require('../lib/account-deletion/scope');
  await db.doc(`account_deletion_scheduler/${deletionScope(context.process.env).stateId}`)
    .set({lastFinishedAt: Date.now(), lastRunOk: true});
  assert.equal((await request({receipt, confirmation: 'DELETE'})).code, 202);
});
