const {randomUUID} = require('node:crypto');
const {deletionScope} = require('./scope');

async function purgeCompletedDeletionMetadata(db, now) {
  // Firebase ID tokens last up to an hour. Retain the UID tombstone only for
  // that revocation window, not indefinitely after the account is gone.
  const completed = await db.collection('account_deletions')
    .where('completedAt', '<=', now - 3600000).limit(25).get();
  for (const snapshot of completed.docs) {
    await db.runTransaction(async tx => {
      const current = await tx.get(snapshot.ref);
      if (current.data()?.status === 'complete' && current.data().completedAt <= now - 3600000) tx.delete(snapshot.ref);
    });
  }
  // Receipts contain an opaque random-token hash, status and time only.
  const receipts = await db.collection('account_deletion_receipts')
    .where('completedAt', '<=', now - 30 * 24 * 3600000).limit(25).get();
  if (!receipts.empty) {
    const batch = db.batch();
    for (const receipt of receipts.docs) batch.delete(receipt.ref);
    await batch.commit();
  }
}

// Persist the last attempted UID so a large or failing job cannot monopolize
// the five slots. The scheduler lease prevents overlapping cron runs.
async function runDeletionQueue({db, runJob, now = Date.now, budgetMs = 35000, onlyUid = null}) {
  if (onlyUid !== null && !/^[A-Za-z0-9_-]{1,128}$/.test(onlyUid)) throw Error('Invalid test account scope');
  const stateId = onlyUid === null ? 'round-robin' : deletionScope({ACCOUNT_DELETION_TEST_UID: onlyUid}).stateId;
  const stateRef = db.collection('account_deletion_scheduler').doc(stateId);
  const lease = randomUUID();
  const started = now();
  const state = await db.runTransaction(async tx => {
    const snapshot = await tx.get(stateRef);
    const current = snapshot.data() || {};
    if ((current.leaseUntil || 0) > now()) return null;
    tx.set(stateRef, {lease, leaseUntil: now() + 120000, lastStartedAt: now()}, {merge: true});
    return current;
  });
  if (!state) return {ok: true, busy: true};
  let failed = false;
  let attempted = 0;
  try {
    // A restricted device test must not process another user's request or purge
    // unrelated receipts/tombstones. Its health and lease are separate too.
    if (onlyUid === null) await purgeCompletedDeletionMetadata(db, now());
    const query = db.collection('account_deletions')
      .where('status', 'in', ['queued', 'processing']).orderBy('__name__');
    const testJob = async () => {
      const snapshot = await db.collection('account_deletions').doc(onlyUid).get();
      const docs = ['queued', 'processing'].includes(snapshot.data()?.status) ? [snapshot] : [];
      return {empty: docs.length === 0, docs};
    };
    let jobs = onlyUid !== null ? await testJob() : await (state.after ? query.startAfter(state.after) : query).limit(5).get();
    if (onlyUid === null && jobs.empty && state.after) jobs = await query.limit(5).get();
    for (const [index, job] of jobs.docs.entries()) {
      const remaining = budgetMs - (now() - started);
      if (remaining < 1000) break;
      try {
        // Share the invocation fairly, but do not waste four of five slots
        // when there is only one account waiting for cleanup.
        await runJob(job.ref, Math.floor(remaining / (jobs.docs.length - index)));
      } catch (error) {
        failed = true;
        console.error('Account deletion worker failed', error.code || 'internal');
      }
      attempted++;
      // Advance after failures too: retries resume on the next rotation.
      await stateRef.update({after: job.id});
    }
    const pending = !(onlyUid !== null ? await testJob() : await query.limit(1).get()).empty;
    await stateRef.update({lastFinishedAt: now(), lastRunOk: !failed, attempted, pending,
      ...(!pending ? {after: ''} : {})});
    return {ok: !failed, attempted, pending};
  } catch (error) {
    await stateRef.update({lastFinishedAt: now(), lastRunOk: false}).catch(() => {});
    throw error;
  } finally {
    await db.runTransaction(async tx => {
      const snapshot = await tx.get(stateRef);
      if (snapshot.data()?.lease === lease) tx.update(stateRef, {leaseUntil: 0});
    });
  }
}

module.exports = {runDeletionQueue};
