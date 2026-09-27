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

async function groupCreationFixture() {
  const {TERMS_VERSION} = require('../lib/media-uploads');
  const groups = Array.from({length: 8}, (_, i) => `group${i}`);
  await seed({'users/alice': {username: 'Alice', role: 'user', country: 'Latvia'},
    [`users/alice/legal_acceptances/${TERMS_VERSION}`]: {termsVersion: TERMS_VERSION},
    'media_spot_reservations/event': {uid: 'alice'},
    ...Object.fromEntries(groups.map(id => [`chats/${id}`, {isGroup: true, memberIds: ['alice'], name: id}]))});
  const photo = 'https://media.example/spots/event/users/alice/main.jpg';
  return {db, firestore: admin.firestore, uid: 'alice', publicBaseUrl: 'https://media.example',
    body: {spotId: 'event', topicDescription: 'Meet', spot: {
      name: 'Meet', cityCountry: 'Riga, Latvia', countryCode: 'LV', categories: ['Meet'],
      lat: 56.95, lng: 24.1, startsAt: Date.now() + 3600000, expiresAt: Date.now() + 7200000,
      showOnMapAt: null, lowCarFriendly: false, photoUrl: photo, photoUrls: [photo],
      visibility: 'group', isTemporary: true, sharedGroupIds: groups, status: 'pending',
      addedByUid: 'forged', authorId: 'forged', likeCount: 999,
    }}};
}

test('server atomically creates a spot, topic and all eight links, and handles a lost response', async () => {
  const {createGroupSpot} = require('../lib/group-spot-create');
  const input = await groupCreationFixture();
  const results = await Promise.all([createGroupSpot(input), createGroupSpot(input)]);
  assert.deepEqual(results, [{spotId: 'event', status: 'pending'}, {spotId: 'event', status: 'pending'}]);
  const spot = (await db.doc('spots/event').get()).data();
  assert.equal(spot.addedByUid, 'alice');
  assert.equal(spot.likeCount, 0);
  assert.equal(spot.lowCarFriendly, false);
  assert.equal(spot.showOnMapAt, null);
  assert.equal(spot.sharedGroups.length, 8);
  const topic = (await db.doc('forum_topics/temporary_spot_event').get()).data();
  assert.equal(topic.authorId, 'alice');
  assert.equal(topic.status, 'pending');
  // Membership in only the last group must still permit reading the event.
  const {TERMS_VERSION} = require('../lib/media-uploads');
  await seed({'users/bob': {role: 'user', country: 'Latvia'},
    [`users/bob/legal_acceptances/${TERMS_VERSION}`]: {termsVersion: TERMS_VERSION}});
  await db.doc('chats/group7').update({memberIds: ['alice', 'bob']});
  await db.doc('spots/event').update({status: 'approved'});
  await assertSucceeds(getDoc(doc(env.authenticatedContext('bob').firestore(), 'spots/event')));
  for (const group of input.body.spot.sharedGroupIds) {
    assert.deepEqual((await db.doc(`chats/${group}/spot_links/event`).get()).data(),
      {spotId: 'event', authorUid: 'alice', published: false});
  }
  input.body.spot.name = 'Changed';
  await assert.rejects(createGroupSpot(input), {status: 409});
});

test('failed topic creation rolls back the spot and links', async () => {
  const {createGroupSpot} = require('../lib/group-spot-create');
  const input = await groupCreationFixture();
  await db.doc('forum_topics/temporary_spot_event').set({authorId: 'bob'});
  await assert.rejects(createGroupSpot(input));
  assert.equal((await db.doc('spots/event').get()).exists, false);
  assert.equal((await db.collectionGroup('spot_links').get()).empty, true);
  assert.equal((await db.doc('forum_topics/temporary_spot_event').get()).data().authorId, 'bob');
});

test('regional moderators can publish in their own country', async () => {
  const {createGroupSpot} = require('../lib/group-spot-create');
  const input = await groupCreationFixture();
  await db.doc('users/alice').update({role: 'moderator', moderatorCountryCodes: ['LV']});
  input.body.spot.status = 'approved';
  input.body.spot.showOnMapAt = input.body.spot.startsAt - 3600000;
  await createGroupSpot(input);
  assert.equal((await db.doc('forum_topics/temporary_spot_event').get()).data().status, 'approved');
  assert.equal((await db.doc('chats/group7/spot_links/event').get()).data().published, true);
});

for (const scenario of ['consent', 'deletion', 'ban', 'membership', 'group-ban', 'reservation', 'region', 'approval', 'photo', 'expiry', 'ninth-group']) {
  test(`group creation rejects ${scenario} without partial writes`, async () => {
    const {createGroupSpot} = require('../lib/group-spot-create');
    const input = await groupCreationFixture();
    const {TERMS_VERSION} = require('../lib/media-uploads');
    if (scenario === 'consent') await db.doc(`users/alice/legal_acceptances/${TERMS_VERSION}`).delete();
    if (scenario === 'deletion') await db.doc('account_deletions/alice').set({status: 'queued'});
    if (scenario === 'ban') await db.doc('users/alice').update({banned: true});
    if (scenario === 'membership') await db.doc('chats/group7').update({memberIds: []});
    if (scenario === 'group-ban') await db.doc('chats/group7').update({bannedMemberIds: ['alice']});
    if (scenario === 'reservation') await db.doc('media_spot_reservations/event').update({uid: 'bob'});
    if (scenario === 'region') await db.doc('app_config/main').set({bannedCountryCodes: ['LV']});
    if (scenario === 'approval') input.body.spot.status = 'approved';
    if (scenario === 'photo') input.body.spot.photoUrls[0] = input.body.spot.photoUrl = 'https://media.example/spots/event/users/bob/main.jpg';
    if (scenario === 'expiry') input.body.spot.expiresAt = Date.now() - 1;
    if (scenario === 'ninth-group') input.body.spot.sharedGroupIds.push('group8');
    await assert.rejects(createGroupSpot(input), error => [400, 403].includes(error.status));
    assert.equal((await db.doc('spots/event').get()).exists, false);
    assert.equal((await db.doc('forum_topics/temporary_spot_event').get()).exists, false);
    assert.equal((await db.collectionGroup('spot_links').get()).empty, true);
  });
}

test('queue wraps fairly, retries failures, and records scheduler evidence', async () => {
  await seed(Object.fromEntries(['a', 'b', 'c', 'd', 'e', 'f', 'g'].map(uid => [
    `account_deletions/${uid}`, {status: 'queued'},
  ])));
  const attempts = [];
  const runJob = async (ref, budget) => {
    assert.ok(budget >= 1000 && budget <= 35000);
    attempts.push(ref.id);
    if (ref.id === 'a') throw Object.assign(new Error('synthetic failure'), {code: 'test'});
  };
  assert.equal((await runDeletionQueue({db, runJob})).ok, false);
  assert.deepEqual(attempts, ['a', 'b', 'c', 'd', 'e']);
  attempts.length = 0;
  assert.equal((await runDeletionQueue({db, runJob})).ok, false);
  assert.deepEqual(attempts, ['f', 'g', 'a', 'b', 'c']);
  const state = (await db.doc('account_deletion_scheduler/round-robin').get()).data();
  assert.equal(state.after, 'c');
  assert.equal(state.lastAttempted, 5);
  assert.equal(state.lastRunOk, false);
  assert.equal(state.leaseUntil, 0);
  assert.ok(state.lastFinishedAt >= state.lastStartedAt);
});

test('queue lease and total budget prevent overlapping and unbounded work', async () => {
  const state = db.doc('account_deletion_scheduler/round-robin');
  await state.set({leaseUntil: Date.now() + 60000});
  assert.equal((await runDeletionQueue({db, runJob: () => assert.fail('lease held')})).busy, true);
  await state.delete();
  await seed({'account_deletions/a': {status: 'queued'}, 'account_deletions/b': {status: 'queued'}});
  let clock = 1000;
  const result = await runDeletionQueue({db, now: () => clock, runJob: async () => {clock += 35000;}});
  assert.equal(result.attempted, 1);
  assert.equal((await state.get()).data().after, 'a');
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

test('upload ledger survives abandoned spot creation and cleanup retries', async () => {
  const {reserveUpload, uploadId, TERMS_VERSION} = require('../lib/media-uploads');
  await seed({'users/alice': {uid: 'alice'},
    [`users/alice/legal_acceptances/${TERMS_VERSION}`]: {termsVersion: TERMS_VERSION}});
  const key = 'spots/abandoned/users/alice/gallery/photo.jpg';
  await reserveUpload({db, uid: 'alice', key});
  assert.equal((await db.doc(`media_uploads/${uploadId(key)}`).get()).data().uid, 'alice');
  assert.equal((await db.doc('spots/abandoned').get()).exists, false);
  const jobRef = db.doc('account_deletions/alice');
  await jobRef.set({status: 'queued', receiptHash: 'receipt'});
  await assert.rejects(reserveUpload({db, uid: 'alice', key}), {status: 403});
  let failed = true;
  const keys = [];
  const media = {deletePrefixPage: async () => true, deleteObject: async key => {
    keys.push(key); if (failed) throw new Error('storage failed');
  }};
  await assert.rejects(processDeletion({db, listPage, jobRef, auth: auth(), media}), /storage failed/);
  assert.equal((await db.doc(`media_uploads/${uploadId(key)}`).get()).exists, true);
  failed = false;
  await processDeletion({db, listPage, jobRef, auth: auth(), media, budgetMs: 100000});
  assert.equal((await jobRef.get()).data().status, 'complete');
  assert.deepEqual(keys, [key, key]);
  assert.equal((await db.doc(`media_uploads/${uploadId(key)}`).get()).exists, false);
});

test('uploads enforce consent, active accounts, ownership and immutable key ownership', async () => {
  const {reserveUpload, TERMS_VERSION} = require('../lib/media-uploads');
  await seed({'users/alice': {uid: 'alice'}, 'users/bob': {uid: 'bob', role: 'admin'}});
  await assert.rejects(reserveUpload({db, uid: 'alice', key: 'users/alice/a.jpg'}), {status: 403});
  for (const uid of ['alice', 'bob']) {
    await db.doc(`users/${uid}/legal_acceptances/${TERMS_VERSION}`).set({termsVersion: TERMS_VERSION});
  }
  await assert.rejects(reserveUpload({db, uid: 'bob', key: 'users/alice/a.jpg'}), {status: 403});
  await reserveUpload({db, uid: 'alice', key: 'spots/new/users/alice/a.jpg'});
  await assert.rejects(reserveUpload({db, uid: 'bob', key: 'spots/new/users/bob/b.jpg'}), {status: 403});
  await db.doc('spots/new').set({addedByUid: 'alice'});
  await assert.rejects(reserveUpload({db, uid: 'bob', key: 'spots/new/users/alice/a.jpg'}), {status: 403});
  await reserveUpload({db, uid: 'bob', key: 'spots/new/users/bob/b.jpg'});
  await db.doc('account_deletions/alice').set({status: 'queued'});
  await assert.rejects(reserveUpload({db, uid: 'bob', key: 'spots/new/users/bob/c.jpg'}), {status: 403});
  await db.doc('users/bob').update({banned: true});
  await assert.rejects(reserveUpload({db, uid: 'bob', key: 'users/bob/a.jpg'}), {status: 403});
  const client = env.authenticatedContext('bob').firestore();
  await assertFails(setDoc(doc(client, 'media_uploads/forged'), {uid: 'alice', key: 'users/bob/a.jpg'}));
  await assertFails(setDoc(doc(client, 'media_spot_reservations/forged'), {uid: 'alice'}));
});

test('a deletion queued during signing prevents the signed URL from being returned', async () => {
  const {createUploadHandler, TERMS_VERSION} = require('../lib/media-uploads');
  await seed({'users/alice': {uid: 'alice'},
    [`users/alice/legal_acceptances/${TERMS_VERSION}`]: {termsVersion: TERMS_VERSION}});
  const handler = createUploadHandler({db, auth: {verifyIdToken: async () => ({uid: 'alice'})},
    sign: async () => {
      await db.doc('account_deletions/alice').set({status: 'queued'});
      return {uploadUrl: 'https://synthetic.invalid/signed'};
    }});
  const res = {setHeader() {}, status(code) {this.code = code; return this;}, json(data) {this.data = data;}};
  await handler({method: 'POST', headers: {authorization: 'Bearer synthetic'},
    body: {path: 'users/alice/a.jpg', contentType: 'image/jpeg'}}, res);
  assert.equal(res.code, 403);
  assert.equal(res.data.uploadUrl, undefined);
  assert.equal((await db.collection('media_uploads').get()).empty, true);
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
    'spots/spot1/comments/bob': {userId: 'bob', text: 'reply to removed spot'},
    'forum_topics/alice_topic': {userId: 'alice', text: 'erase topic'},
    'forum_topics/alice_topic/replies/bob': {userId: 'bob', text: 'reply to removed topic'},
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
  for (const key of ['users/alice', 'users/alice/legal_acceptances/v1', 'global_chat/mine', 'chats/orphan/messages/mine', 'spots/spot1',
    'spots/spot1/comments/bob', 'forum_topics/alice_topic', 'forum_topics/alice_topic/replies/bob']) {
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

test('indexed relationships remove copied spot/topic records without an author UID', async () => {
  const jobRef = db.doc('account_deletions/alice');
  await seed({
    [jobRef.path]: {status: 'queued', receiptHash: 'receipt'},
    'users/alice': {deleted: true},
    'spots/a': {addedByUid: 'alice'},
    'spots/b': {addedByUid: 'bob'},
    'users/bob': {uid: 'bob', copies: ['https://media.example/spots/a/main.jpg', 'https://media.example/spots/b/main.jpg']},
    'forum_topics/copied': {spotId: 'a', description: 'copy of deleted spot'},
    'forum_topics/copied/replies/bob': {userId: 'bob', text: 'removed with source'},
    'spot_reviews/r': {spotId: 'a', userId: 'bob'},
    'spot_reviews/keep': {spotId: 'b', userId: 'bob'},
    'chats/group/spot_links/a': {spotId: 'a'},
    'user_notifications/n': {userId: 'bob', data: {topicId: 'copied'}, body: 'copy'},
    'user_notifications/keep': {userId: 'bob', data: {spotId: 'b'}},
  });
  let calls = 0;
  while ((await jobRef.get()).data().status !== 'complete' && calls++ < 50) {
    await processDeletion({db, listPage, jobRef, auth: auth(), maxDocuments: 10,
      media: {deletePrefixPage: async () => true}});
  }
  assert.equal((await jobRef.get()).data().status, 'complete');
  for (const path of ['spots/a', 'forum_topics/copied', 'forum_topics/copied/replies/bob',
    'spot_reviews/r', 'chats/group/spot_links/a', 'user_notifications/n']) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  for (const path of ['spots/b', 'spot_reviews/keep', 'user_notifications/keep']) {
    assert.equal((await db.doc(path).get()).exists, true, path);
  }
  assert.deepEqual((await db.doc('users/bob').get()).data().copies, ['', 'https://media.example/spots/b/main.jpg']);
});

test('indexed quote cleanup catches a reply added after the collection scan', async () => {
  const {createHash} = require('node:crypto');
  const jobRef = db.doc('account_deletions/alice');
  const path = 'global_chat/source';
  await seed({[jobRef.path]: {status: 'processing', initialized: true, receiptHash: 'receipt'},
    'global_chat/late': {userId: 'bob', text: 'keep', replyToMessageId: 'source', replyToText: 'erase'}});
  await jobRef.collection('tasks').doc(createHash('sha256').update(`quotes:${path}`).digest('hex'))
    .set({kind: 'quotes', path});
  await processDeletion({db, listPage, jobRef, auth: auth(), media: {}, budgetMs: 100000});
  const reply = (await db.doc('global_chat/late').get()).data();
  assert.equal(reply.replyToText, '');
  assert.equal(reply.text, 'keep');
});

test('deleting a copied parent restarts a partially scanned child collection', async () => {
  const {createHash} = require('node:crypto');
  const jobRef = db.doc('account_deletions/alice');
  const childPath = 'forum_topics/copied/replies';
  await seed({[jobRef.path]: {status: 'processing', initialized: true, receiptHash: 'receipt'},
    'forum_topics/copied': {spotId: 'removed'},
    [`${childPath}/earlier`]: {userId: 'bob', text: 'already scanned'},
    [`${childPath}/later`]: {userId: 'bob', text: 'pending'}});
  await jobRef.collection('tasks').doc('0000').set({kind: 'collection', path: 'forum_topics',
    pendingPaths: ['forum_topics/copied'], lastPage: true, relationField: 'spotId', relationValue: 'removed'});
  await jobRef.collection('tasks').doc(createHash('sha256').update(childPath).digest('hex')).set({
    kind: 'collection', path: childPath, pendingPaths: [`${childPath}/later`], lastPage: true});
  await processDeletion({db, listPage, jobRef, auth: auth(), media: {}, budgetMs: 100000});
  assert.equal((await db.collection(childPath).get()).empty, true);
  assert.equal((await jobRef.get()).data().status, 'complete');
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
    module, Buffer, Date, console, process: {env: {ACCOUNT_DELETION_ENABLED: 'true',
      ACCOUNT_DELETION_LEGACY_UPLOADS_RETIRED: 'true', CRON_SECRET: 'local-test-only'}},
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
  context.process.env.ACCOUNT_DELETION_LEGACY_UPLOADS_RETIRED = 'false';
  assert.equal((await request({receipt, confirmation: 'DELETE'})).code, 503);
  assert.equal((await db.doc('account_deletions/alice').get()).exists, false);
  context.process.env.ACCOUNT_DELETION_LEGACY_UPLOADS_RETIRED = 'true';
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
