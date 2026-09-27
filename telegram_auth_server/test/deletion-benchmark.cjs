// Synthetic local throughput only. Never use production credentials or data.
const fs = require('node:fs');
const admin = require('firebase-admin');
const {processDeletion} = require('../lib/account-deletion/worker');
const {collectionPager} = require('../lib/account-deletion/list-page');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') {
  throw new Error('Run only against the local CCS test emulator');
}
const app = admin.initializeApp({projectId: 'demo-ccs-deletion-benchmark'});
const db = app.firestore();
async function main() {
  const count = 1000;
  await fetch('http://127.0.0.1:18080/emulator/v1/projects/demo-ccs-deletion-benchmark/databases/(default)/documents', {method: 'DELETE'});
  for (let offset = 0; offset < count; offset += 250) {
    const batch = db.batch();
    for (let i = offset; i < offset + 250; i++) {
      batch.set(db.doc(`benchmark_rows/${String(i).padStart(5, '0')}`), {userId: i % 10 === 0 ? 'synthetic' : 'other', text: 'Synthetic fixture'});
    }
    await batch.commit();
  }
  const jobRef = db.doc('account_deletions/synthetic');
  await jobRef.set({status: 'queued', receiptHash: 'synthetic-only'});
  const durationsMs = [];
  const listPage = collectionPager({db});
  while ((await jobRef.get()).data().status !== 'complete' && durationsMs.length < 100) {
    const started = Date.now();
    await processDeletion({db, listPage, jobRef, budgetMs: 7000, maxDocuments: 250,
      auth: {updateUser: async () => {}, revokeRefreshTokens: async () => {}, deleteUser: async () => {}},
      media: {deletePrefixPage: async () => true}});
    durationsMs.push(Date.now() - started);
  }
  const report = {environment: 'local emulator; synthetic data and fake Auth/R2; not a production SLA',
    documents: count, budgetMs: 7000, maxDocuments: 250, invocations: durationsMs.length,
    durationsMs, completed: (await jobRef.get()).data().status === 'complete',
    remainingUnrelatedDocuments: (await db.collection('benchmark_rows').count().get()).data().count,
    checkedAt: new Date().toISOString()};
  fs.writeFileSync('build/deletion-benchmark.json', JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
}
main().finally(() => app.delete()).catch(error => {console.error(error); process.exitCode = 1;});
