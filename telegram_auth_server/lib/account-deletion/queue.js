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
    tx.set(stateRef, {lease, leaseUntil: now() + 120000, lastStartedAt: now()}, {merge: true});
    return current;
  });
  if (!state) return {ok: true, busy: true};
  let failed = false;
  let attempted = 0;
  let finished = false;
  try {
    const query = db.collection('account_deletions')
      .where('status', 'in', ['queued', 'processing']).orderBy('__name__');
    const page = await (state.after ? query.startAfter(state.after) : query).limit(5).get();
    const jobs = [...page.docs];
    if (jobs.length < 5 && state.after) {
      const wrapped = await query.endAt(state.after).limit(5 - jobs.length).get();
      jobs.push(...wrapped.docs);
    }
    for (const [index, job] of jobs.entries()) {
      const remaining = budgetMs - (now() - started);
      if (remaining < 1000) break;
      attempted++;
      try {
        // A single queued account can use the available budget. Under load each
        // remaining account keeps a fair slice; failures do not consume its slot.
        await runJob(job.ref, Math.floor(remaining / (jobs.length - index)));
      } catch (error) {
        failed = true;
        console.error('Account deletion worker failed', error.code || 'internal');
      }
      // Advance after failures too: retries resume on the next rotation.
      await stateRef.update({after: job.id});
    }
    finished = true;
    return {ok: !failed, attempted};
  } finally {
    await db.runTransaction(async tx => {
      const snapshot = await tx.get(stateRef);
      if (snapshot.data()?.lease === lease) tx.update(stateRef, {
        leaseUntil: 0, lastFinishedAt: now(), lastDurationMs: now() - started,
        lastAttempted: attempted, lastRunOk: finished && !failed,
      });
    });
  }
}

module.exports = {runDeletionQueue};
