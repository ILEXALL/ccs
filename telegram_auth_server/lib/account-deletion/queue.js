const {randomUUID} = require('node:crypto');

// Persist the last attempted UID so a large or failing job cannot monopolize
// the five daily slots. The scheduler lease prevents overlapping cron runs.
async function runDeletionQueue({db, runJob, now = Date.now, budgetMs = 35000}) {
  const stateRef = db.collection('account_deletion_scheduler').doc('round-robin');
  const lease = randomUUID();
  const started = now();
  const state = await db.runTransaction(async tx => {
    const snapshot = await tx.get(stateRef);
    const current = snapshot.data() || {};
    if ((current.leaseUntil || 0) > now()) return null;
    tx.set(stateRef, {lease, leaseUntil: now() + 120000}, {merge: true});
    return current;
  });
  if (!state) return {ok: true, busy: true};
  let failed = false;
  try {
    const query = db.collection('account_deletions')
      .where('status', 'in', ['queued', 'processing']).orderBy('__name__');
    let jobs = await (state.after ? query.startAfter(state.after) : query).limit(5).get();
    if (jobs.empty && state.after) jobs = await query.limit(5).get();
    for (const job of jobs.docs) {
      const remaining = budgetMs - (now() - started);
      if (remaining < 1000) break;
      try {
        await runJob(job.ref, Math.min(7000, remaining));
      } catch (error) {
        failed = true;
        console.error('Account deletion worker failed', error.code || 'internal');
      }
      // Advance after failures too: retries resume on the next rotation.
      await stateRef.update({after: job.id});
    }
    return {ok: !failed};
  } finally {
    await db.runTransaction(async tx => {
      const snapshot = await tx.get(stateRef);
      if (snapshot.data()?.lease === lease) tx.update(stateRef, {leaseUntil: 0});
    });
  }
}

module.exports = {runDeletionQueue};
