// No Firebase/R2 credentials or user identifiers belong in this Worker.
// Its secret permits processing already-confirmed deletion requests only.
export default {
  async scheduled(_event, env) {
    const verify = env.ENABLED !== 'true' && env.VERIFY_ONLY === 'true';
    if (env.ENABLED !== 'true' && !verify) return;
    if (!env.ACCOUNT_DELETION_WORKER_SECRET) throw new Error('Deletion scheduler secret missing');
    const response = await fetch(`https://ccs-wine.vercel.app/api/account-deletion${verify ? '?action=verify' : ''}`, {
      method: 'GET',
      headers: {Authorization: `Bearer ${env.ACCOUNT_DELETION_WORKER_SECRET}`},
      redirect: 'manual',
      signal: AbortSignal.timeout(55000),
    });
    // Never log response bodies: only aggregate counters are expected, but
    // upstream proxies can return other information during an incident.
    if (!response.ok && !(verify && response.status === 503)) throw new Error(`Deletion batch returned HTTP ${response.status}`);
    const result = await response.json();
    if (verify) {
      if (result.mode !== 'verify') throw new Error('Unexpected verification response');
      console.log(JSON.stringify({ok: result.ok === true, mode: 'verify', r2List: result.r2List === true,
        firebaseAbsent: result.firebaseAbsent === true,
        firebaseList: result.firebaseList === true, firebaseMetadata: result.firebaseMetadata === true,
        firebaseSoftDeleteSeconds: result.firebaseSoftDeleteSeconds == null ? null : Number(result.firebaseSoftDeleteSeconds),
        firebaseRetentionSeconds: result.firebaseRetentionSeconds == null ? null : Number(result.firebaseRetentionSeconds)}));
      if (!response.ok || result.ok !== true) throw new Error('Storage verification failed');
      return;
    }
    if (result.ok !== true) throw new Error('Deletion batch did not succeed');
    console.log(JSON.stringify({ok: true, busy: result.busy === true,
      attempted: Number(result.attempted || 0), pending: result.pending === true}));
  },
  async fetch() { return new Response('Not found', {status: 404}); },
};
