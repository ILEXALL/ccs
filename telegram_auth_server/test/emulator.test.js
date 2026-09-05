const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, Timestamp, serverTimestamp, setLogLevel } = require('firebase/firestore');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') {
  throw new Error('Tests require the local CCS emulator at 127.0.0.1:18080');
}
const projectId = 'demo-ccs-tests';
// Expected permission denials are asserted below; keep the console readable.
setLogLevel('silent');
let env;
const client = (uid) => env.authenticatedContext(uid).firestore();
const spot = (uid = 'owner', status = 'pending') => ({
  addedByUid: uid, name: 'Synthetic spot', cityCountry: 'Riga, Latvia',
  countryCode: 'LV', categories: ['photo'], status, rating: 0,
});
const decision = (uid, status = 'approved') => ({
  status, reviewedByUid: uid, reviewedBy: uid,
  reviewedAt: serverTimestamp(), updatedAt: serverTimestamp(),
  rejectionReason: status === 'rejected' ? 'Test rejection' : '',
  rating: status === 'approved' ? 4.5 : 0,
});
async function seed(rows) {
  await env.withSecurityRulesDisabled(async (context) => {
    for (const [key, data] of Object.entries(rows)) await setDoc(doc(context.firestore(), key), data);
  });
}
before(async () => {
  env = await initializeTestEnvironment({ projectId, firestore: { host: '127.0.0.1', port: 18080 } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed({
    'users/owner': { role: 'user' }, 'users/other': { role: 'user' },
    'users/mod': { role: 'moderator', moderatorCountryCodes: ['LV'] },
    'users/mod2': { role: 'moderator', moderatorCountryCodes: ['LV'] },
    'users/admin': { role: 'admin' }, 'users/banned': { role: 'user', banned: true },
  });
});
after(async () => { if (env) await env.cleanup(); });

test('[rules XP] owner reads own stats, outsider cannot, no client can write XP', async () => {
  await seed({ 'xp_user_stats/owner': { userId: 'owner', xpTotal: 50 } });
  await assertSucceeds(getDoc(doc(client('owner'), 'xp_user_stats/owner')));
  await assertFails(getDoc(doc(client('other'), 'xp_user_stats/owner')));
  for (const uid of ['owner', 'mod', 'admin']) {
    await assertFails(updateDoc(doc(client(uid), 'xp_user_stats/owner'), { xpTotal: 9999 }));
    await assertFails(setDoc(doc(client(uid), 'xp_transactions/forged'), { userId: uid, amount: 9999 }));
  }
});

test('[rules spots] user creates pending spot but cannot self-approve or forge author', async () => {
  await assertSucceeds(setDoc(doc(client('owner'), 'spots/new'), spot()));
  await assertFails(setDoc(doc(client('owner'), 'spots/approved'), spot('owner', 'approved')));
  await assertFails(setDoc(doc(client('owner'), 'spots/forged'), spot('other')));
  await assertFails(setDoc(doc(client('banned'), 'spots/banned'), spot('banned')));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'spots/anon'), spot()));
});

test('[rules moderation] regional moderator approves and admin rejects unlocked spots', async () => {
  await seed({ 'spots/a': spot(), 'spots/b': spot() });
  await assertSucceeds(updateDoc(doc(client('mod'), 'spots/a'), decision('mod')));
  await assertSucceeds(updateDoc(doc(client('admin'), 'spots/b'), decision('admin', 'rejected')));
});

test('[rules moderation] owner and out-of-region moderator cannot approve', async () => {
  await seed({ 'spots/a': spot(), 'users/foreign': { role: 'moderator', moderatorCountryCodes: ['EE'] } });
  for (const uid of ['owner', 'foreign']) {
    await assertFails(updateDoc(doc(client(uid), 'spots/a'), decision(uid)));
  }
});

test('[rules moderation] live lock allows its reviewer and blocks another moderator', async () => {
  await seed({ 'spots/a': spot(), 'spot_review_locks/a': {
    reviewerUid: 'mod', sessionId: 'synthetic-session', expiresAt: Timestamp.fromMillis(Date.now() + 600000),
  } });
  await assertFails(updateDoc(doc(client('mod2'), 'spots/a'), decision('mod2')));
  await assertSucceeds(updateDoc(doc(client('mod'), 'spots/a'), decision('mod')));
});

test('[rules moderation] expired lock does not prevent a new reviewer', async () => {
  await seed({ 'spots/a': spot(), 'spot_review_locks/a': {
    reviewerUid: 'mod', sessionId: 'old', expiresAt: Timestamp.fromMillis(Date.now() - 60000),
  } });
  await assertSucceeds(updateDoc(doc(client('mod2'), 'spots/a'), decision('mod2')));
});

test('[rules moderation] concurrent conflicting decisions accept only one', async () => {
  await seed({ 'spots/a': spot() });
  const outcomes = await Promise.allSettled([
    updateDoc(doc(client('mod'), 'spots/a'), decision('mod')),
    updateDoc(doc(client('mod2'), 'spots/a'), decision('mod2', 'rejected')),
  ]);
  assert.equal(outcomes.filter((x) => x.status === 'fulfilled').length, 1);
});
