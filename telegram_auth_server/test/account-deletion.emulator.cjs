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

test('removes content and orphan descendants, scrubs old reply previews, keeps other members', async () => {
  const ref = db.doc('account_deletions/alice');
  await seed({
    [ref.path]: {status: 'queued', username: 'new_alice', receiptHash: 'receipt'},
    'account_deletion_receipts/receipt': {status: 'processing'},
    'users/alice': {uid: 'alice', deleted: true, name: 'Alice', garage: [{photoUrl: 'private'}]},
    'users/alice/legal_acceptances/v1': {termsVersion: 'v1'},
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
  for (const key of ['users/alice', 'users/alice/legal_acceptances/v1', 'global_chat/mine', 'chats/orphan/messages/mine', 'spots/spot1']) {
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

test('request derives account from fresh authenticated token and receipt exposes only status', async () => {
  const {createHash} = require('node:crypto');
  const module = {exports: {}};
  let token = {uid: 'alice', auth_time: Math.floor(Date.now() / 1000)};
  const calls = [];
  const context = {
    module, Buffer, Date, console, process: {env: {ACCOUNT_DELETION_ENABLED: 'true', CRON_SECRET: 'local-test-only'}},
    require: name => {
      if (name === 'node:crypto') return require(name);
      if (name.endsWith('/firebase-admin')) return {db, admin: {firestore: admin.firestore, auth: () => ({
        verifyIdToken: async (_, revoked) => {assert.equal(revoked, true); return token;},
        updateUser: async (uid, fields) => {calls.push(['disable', uid, fields.disabled]);},
        revokeRefreshTokens: async uid => {calls.push(['revoke', uid]);},
      })}};
      if (name.endsWith('/storage')) return {storageAdapter: () => ({})};
      if (name.endsWith('/worker')) return {};
      if (name.endsWith('/list-page')) return {};
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
});
