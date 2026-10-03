// Destructive benchmark restricted to a separate, local demo database.
const admin = require('firebase-admin');
const path = require('node:path');
const implementation = process.env.CCS_DELETION_BENCHMARK_IMPLEMENTATION || path.resolve(__dirname, '../lib/account-deletion');
const {processDeletion} = require(path.join(implementation, 'worker'));
const {collectionPager} = require(path.join(implementation, 'list-page'));
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw new Error('Local emulator required');
const projectId = 'demo-ccs-deletion-benchmark';
async function main() {
  const app = admin.initializeApp({projectId});
  const db = app.firestore();
  try {
    const cleared = await fetch(`http://127.0.0.1:18080/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method: 'DELETE'});
    if (!cleared.ok) throw new Error('Could not reset local benchmark');
    const unrelated = 2000, owned = 50;
    const writer = db.bulkWriter();
    for (let i = 0; i < unrelated + owned; i++) {
      writer.set(db.doc(`global_chat/m${String(i).padStart(5, '0')}`), {userId: i < owned ? 'alice' : 'bob', text: 'synthetic'});
    }
    await writer.close();
    const jobRef = db.doc('account_deletions/alice');
    await jobRef.set({status: 'queued', receiptHash: 'benchmark'});
    await db.doc('users/alice').set({deleted: true});
    const pager = collectionPager({db});
    let pages = 0;
    const listPage = (...args) => {pages++; return pager(...args);};
    const started = Date.now();
    const batchMs = [];
    while ((await jobRef.get()).data().status !== 'complete' && batchMs.length < 100) {
      const batchStart = Date.now();
      await processDeletion({db, jobRef, listPage, budgetMs: 7000,
        auth: {updateUser: async () => {}, revokeRefreshTokens: async () => {}, deleteUser: async () => {}},
        media: {deletePrefixPage: async () => true}});
      batchMs.push(Date.now() - batchStart);
    }
    const complete = (await jobRef.get()).data().status === 'complete';
    console.log(JSON.stringify({environment: 'local emulator; mocked Auth and storage',
      unrelated, owned, complete, pages, batches: batchMs.length, elapsedMs: Date.now() - started,
      batchMs, dailyScheduleDays: batchMs.length, fiveMinuteScheduleMinutes: batchMs.length * 5}, null, 2));
    if (!complete) process.exitCode = 1;
  } finally { await app.delete(); }
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
