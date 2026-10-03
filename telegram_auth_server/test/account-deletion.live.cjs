// Explicit, bounded production integration test. Not an HTTP handler.
// Run only in a one-off build with the flags below. Never scan real collections.
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {S3Client, PutObjectCommand, HeadObjectCommand, DeleteObjectsCommand} = require('@aws-sdk/client-s3');

async function main() {
  assert.equal(process.env.CCS_RUN_DELETION_SELF_TEST, 'true');
  const run = process.env.CCS_DELETION_SELF_TEST_ID;
  assert.match(run || '', /^[a-f0-9]{24}$/);
  assert.equal(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON).project_id, 'ccsv1-63537');
  assert.equal(process.env.ACCOUNT_DELETION_ENABLED, 'false');
  const {admin, db} = require('../lib/firebase-admin');
  const {processDeletion} = require('../lib/account-deletion/worker');
  const {storageAdapter} = require('../lib/account-deletion/storage');
  const uid = `ccs_delete_test_${run}`, control = `${uid}_control`, chat = `${uid}_chat`;
  const receipt = createHash('sha256').update(`self-test:${run}`).digest('hex');
  const paths = [`users/${uid}`, `users/${control}`, `users/${uid}/private/test`,
    `chats/${chat}`, `chats/${chat}/messages/owned`, `chats/${chat}/messages/reply`];
  const job = db.doc(`account_deletions/${uid}`);
  const receiptRef = db.doc(`account_deletion_receipts/${receipt}`);
  const media = storageAdapter(process.env, {firebaseStorage: admin.storage()});
  const s3 = new S3Client({region: 'auto', endpoint: process.env.R2_ENDPOINT,
    credentials: {accessKeyId: process.env.R2_ACCESS_KEY_ID, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY}});
  const keys = [`users/${uid}/self-test.txt`, `garage/${uid}/self-test.txt`, `users/${control}/self-test.txt`];
  const exists = async Key => {
    try {await s3.send(new HeadObjectCommand({Bucket: process.env.R2_BUCKET_NAME, Key})); return true;}
    catch (error) {if (error.$metadata?.httpStatusCode === 404) return false; throw error;}
  };
  // Preflight every name before creating anything. A retry must never overwrite
  // an existing account, document or object, including earlier test leftovers.
  for (const id of [uid, control]) {
    try {await admin.auth().getUser(id); throw Error('Fixture account already exists');}
    catch (error) {if (error.code !== 'auth/user-not-found') throw error;}
  }
  for (const p of [...paths, job.path, receiptRef.path]) assert.equal((await db.doc(p).get()).exists, false);
  for (const key of keys) assert.equal(await exists(key), false);
  if (process.env.CCS_DELETION_SELF_TEST_VERIFY_ONLY === 'true') {
    for (const name of ['tasks', 'references', 'reply_checks', 'content_checks']) {
      assert.equal((await job.collection(name).limit(1).get()).empty, true);
    }
    console.log('CCS_DELETION_FIXTURE_ABSENCE', JSON.stringify({ok: true, accounts: 2, documents: paths.length + 2,
      objects: keys.length, queueSubcollectionsEmpty: true}));
    return;
  }
  const createdAuth = [], createdDocs = [], createdKeys = [];
  let outcome, cleanupErrors = 0;
  const started = Date.now();
  try {
    for (const id of [uid, control]) {
      await admin.auth().createUser({uid: id, disabled: true}); createdAuth.push(id);
    }
    const fixtures = [
      {uid, username: uid, deleted: true, publicProfile: false},
      {uid: control, username: control, publicProfile: false, sentinel: 'unchanged'},
      {note: 'synthetic private data'},
      {type: 'direct', isGroup: false, memberIds: [uid, control], memberUsernames: [uid, control], memberPhotoUrls: ['', ''], ownerUid: uid},
      {userId: uid, text: 'synthetic owned message'},
      {userId: control, text: 'keep this reply', replyToMessageId: 'owned', replyToUsername: 'old-test-name', replyToText: 'synthetic owned message'},
    ];
    for (let i = 0; i < paths.length; i++) {await db.doc(paths[i]).create(fixtures[i]); createdDocs.push(paths[i]);}
    for (const Key of keys) {
      await s3.send(new PutObjectCommand({Bucket: process.env.R2_BUCKET_NAME, Key,
        Body: 'CCS disposable deletion integration fixture', ContentType: 'text/plain', IfNoneMatch: '*'}));
      createdKeys.push(Key);
    }
    await job.create({status: 'queued', receiptHash: receipt, username: uid});
    // No signed upload URLs were issued for these fixtures. The cooldown itself
    // is covered by emulator tests; this run exercises the real cleanup APIs.
    createdDocs.push(job.path, receiptRef.path);
    const allowed = path => paths.includes(path) || path === job.path || path.startsWith(`${job.path}/`) || path === receiptRef.path;
    const limitedDb = {
      listCollections: async () => [db.collection('users'), db.collection('chats')],
      doc: path => {assert.ok(allowed(path), 'Out-of-scope document'); return db.doc(path);},
      collection: name => {
        assert.ok(['users', 'account_deletion_receipts'].includes(name));
        return {doc: id => {const path = `${name}/${id}`; assert.ok(allowed(path)); return db.doc(path);}};
      },
      runTransaction: callback => db.runTransaction(callback), batch: () => db.batch(),
      recursiveDelete: ref => {assert.equal(ref.path, `users/${uid}`); return db.recursiveDelete(ref);},
    };
    const restrictedAuth = {};
    for (const method of ['updateUser', 'revokeRefreshTokens', 'deleteUser']) {
      restrictedAuth[method] = (id, ...args) => {assert.equal(id, uid); return admin.auth()[method](id, ...args);};
    }
    let injected = false, recovered = false, batches = 0;
    const restrictedMedia = {deletePrefixPage: async prefix => {
      assert.ok([`users/${uid}/`, `garage/${uid}/`].includes(prefix), 'Out-of-scope media');
      if (!injected) {injected = true; throw Error('SELF_TEST_INTERRUPTION');}
      return media.deletePrefixPage(prefix);
    }};
    const listPage = async (collectionPath, pageToken) => {
      assert.equal(pageToken, '');
      const selected = paths.filter(p => p.slice(0, p.lastIndexOf('/')) === collectionPath).sort();
      assert.ok(selected.length, 'Out-of-scope collection');
      return {paths: selected, nextPageToken: ''};
    };
    while ((await job.get()).data()?.status !== 'complete' && batches++ < 80) {
      try {await processDeletion({db: limitedDb, auth: restrictedAuth, media: restrictedMedia, jobRef: job,
        listPage, maxDocuments: 2, budgetMs: 10000});}
      catch (error) {
        if (error.message !== 'SELF_TEST_INTERRUPTION') throw error;
        assert.equal((await job.get()).data().leaseUntil, 0);
        assert.equal((await admin.auth().getUser(uid)).disabled, true);
        recovered = true;
      }
    }
    assert.equal((await job.get()).data().status, 'complete');
    assert.ok(injected && recovered);
    await assert.rejects(admin.auth().getUser(uid), error => error.code === 'auth/user-not-found');
    assert.equal((await admin.auth().getUser(control)).uid, control);
    for (const p of [paths[0], paths[2], paths[4]]) assert.equal((await db.doc(p).get()).exists, false);
    assert.deepEqual((await db.doc(paths[1]).get()).data(), fixtures[1]);
    const reply = (await db.doc(paths[5]).get()).data();
    assert.equal(reply.text, 'keep this reply'); assert.equal(reply.replyToText, '');
    assert.deepEqual((await db.doc(paths[3]).get()).data().memberIds, [control]);
    assert.equal((await receiptRef.get()).data().status, 'complete');
    assert.deepEqual(await Promise.all(keys.map(exists)), [false, false, true]);
    for (const name of ['tasks', 'references', 'reply_checks', 'content_checks']) assert.equal((await job.collection(name).limit(1).get()).empty, true);
    outcome = {ok: true, authDeleted: true, privateDataDeleted: true, ownedMessageDeleted: true,
      quoteCleared: true, controlAccountAndFilePreserved: true, interruptedBatchRecovered: true,
      r2ObjectsDeleted: 2, batches, elapsedMs: Date.now() - started, scope: 'synthetic-fixtures-only'};
  } finally {
    // All cleanup references originate in this run's successful creations.
    for (const id of createdAuth) {
      try {await admin.auth().deleteUser(id);} catch (error) {if (error.code !== 'auth/user-not-found') cleanupErrors++;}
    }
    for (const p of createdDocs.filter(p => p.split('/').length === 2)) {
      try {await db.recursiveDelete(db.doc(p));} catch (_) {cleanupErrors++;}
    }
    if (createdKeys.length) {
      try {
        const result = await s3.send(new DeleteObjectsCommand({Bucket: process.env.R2_BUCKET_NAME,
          Delete: {Objects: createdKeys.map(Key => ({Key})), Quiet: true}}));
        if (result.Errors?.length) cleanupErrors++;
      } catch (_) {cleanupErrors++;}
    }
    console.log('CCS_DELETION_TEST_CLEANUP', JSON.stringify({ok: cleanupErrors === 0}));
  }
  assert.equal(cleanupErrors, 0, 'Fixture cleanup incomplete');
  console.log('CCS_DELETION_LIVE_TEST', JSON.stringify(outcome));
}
main().catch(error => {
  console.error('CCS_DELETION_LIVE_TEST_FAILED', JSON.stringify({code: error.code || 'test-failed',
    assertion: error.name === 'AssertionError' ? error.message : undefined}));
  process.exitCode = 1;
});
