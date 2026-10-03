const {createHash, timingSafeEqual} = require('node:crypto');
const {admin, db} = require('../lib/firebase-admin');
const {processDeletion} = require('../lib/account-deletion/worker');
const {storageAdapter} = require('../lib/account-deletion/storage');
const {collectionPager} = require('../lib/account-deletion/list-page');
const {runDeletionQueue} = require('../lib/account-deletion/queue');
const {deletionScope} = require('../lib/account-deletion/scope');
const hash = value => createHash('sha256').update(value).digest('hex');
const same = (a, b) => typeof a === 'string' && typeof b === 'string' &&
  Buffer.byteLength(a) === Buffer.byteLength(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  try {
    const scope = deletionScope(process.env);
    if (req.method === 'GET') {
      const secrets = [process.env.CRON_SECRET, process.env.ACCOUNT_DELETION_WORKER_SECRET].filter(Boolean);
      if (!secrets.some(secret => same(req.headers.authorization, `Bearer ${secret}`))) {
        return res.status(401).json({error: 'Unauthorized'});
      }
      // A read-only connection check must never advance jobs or update worker
      // health: successful diagnostics are not evidence that cleanup is running.
      if (req.query?.action === 'verify') {
        const media = storageAdapter(process.env, {firebaseStorage: admin.storage()});
        const checks = await media.verifyAccess();
        return res.status(checks.ok ? 200 : 503).json({mode: 'verify', ...checks});
      }
      if (!scope.enabled) {
        return res.status(503).json({error: 'Account deletion is temporarily unavailable'});
      }
      const media = storageAdapter(process.env, {firebaseStorage: admin.storage()});
      const listPage = collectionPager({db, credential: admin.app().options.credential});
      const result = await runDeletionQueue({db, onlyUid: scope.onlyUid, runJob: (jobRef, budgetMs) =>
        processDeletion({db, auth: admin.auth(), media, listPage, jobRef, budgetMs})});
      return res.status(result.ok ? 200 : 503).json(result);
    }
    if (req.method !== 'POST') return res.status(405).json({error: 'Method not allowed'});
    if (req.body?.action === 'status') {
      const receipt = req.body.receipt;
      if (typeof receipt !== 'string' || !/^[a-f0-9]{64}$/.test(receipt)) return res.status(400).json({error: 'Invalid receipt'});
      const result = await db.collection('account_deletion_receipts').doc(hash(receipt)).get();
      return res.json({status: result.data()?.status || 'unknown'});
    }
    // Fail closed until production storage, scheduler and verified deployment
    // have been configured. Never accept a request that has no working worker.
    if (!scope.enabled || !process.env.CRON_SECRET) {
      return res.status(503).json({error: 'Account deletion is temporarily unavailable'});
    }
    storageAdapter(process.env, {firebaseStorage: admin.storage()});
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return res.status(401).json({error: 'Sign in required'});
    let token;
    try { token = await admin.auth().verifyIdToken(header.slice(7), true); }
    catch (_) { return res.status(401).json({error: 'Sign in again before deleting your account'}); }
    if (scope.onlyUid !== null && token.uid !== scope.onlyUid) {
      return res.status(503).json({error: 'Account deletion is temporarily unavailable'});
    }
    if (!token.auth_time || Date.now() / 1000 - token.auth_time > 300) {
      return res.status(401).json({error: 'Sign in again before deleting your account'});
    }
    // Do not accept new destructive requests when the frequent scheduler is
    // offline. The daily cron still retries already-accepted jobs.
    const scheduler = (await db.collection('account_deletion_scheduler').doc(scope.stateId).get()).data();
    if (!scheduler?.lastFinishedAt || scheduler.lastRunOk !== true ||
        Date.now() - scheduler.lastFinishedAt > 15 * 60 * 1000) {
      return res.status(503).json({error: 'Account deletion is temporarily unavailable. Please try again later.'});
    }
    if (req.body?.confirmation !== 'DELETE') return res.status(400).json({error: 'Confirmation required'});
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(token.uid)) return res.status(400).json({error: 'Unsupported account identifier'});
    const receipt = req.body.receipt;
    if (typeof receipt !== 'string' || !/^[a-f0-9]{64}$/.test(receipt)) return res.status(400).json({error: 'Invalid receipt'});
    const receiptHash = hash(receipt);
    const jobRef = db.collection('account_deletions').doc(token.uid);
    await db.runTransaction(async tx => {
      const userRef = db.collection('users').doc(token.uid);
      const [existing, profile] = await Promise.all([tx.get(jobRef), tx.get(userRef)]);
      if (existing.exists) {
        if (existing.data().receiptHash === receiptHash) return;
        throw Object.assign(new Error('Deletion already requested'), {status: 409});
      }
      tx.create(jobRef, {status: 'queued', receiptHash, username: profile.data()?.username || '', requestedAt: Date.now()});
      tx.create(db.collection('account_deletion_receipts').doc(receiptHash), {status: 'processing'});
      tx.set(userRef, {deleted: true, publicProfile: false, deletionRequestedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    });
    await admin.auth().updateUser(token.uid, {disabled: true});
    await admin.auth().revokeRefreshTokens(token.uid);
    return res.status(202).json({status: 'processing', receipt});
  } catch (error) {
    console.error('Account deletion operation failed', error.code || error.status || 'internal');
    return res.status(error.status || 500).json({error: error.status ? error.message : 'Could not complete the request. Please retry.'});
  }
};
