const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, runTransaction, Timestamp, serverTimestamp, setLogLevel } = require('firebase/firestore');

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
  await seed(Object.fromEntries(['owner', 'other', 'mod', 'mod2', 'admin', 'banned'].map(uid => [
    `users/${uid}/legal_acceptances/2026-09-24`,
    {termsVersion: '2026-09-24', acceptedAt: Timestamp.fromMillis(1)},
  ])));
});
after(async () => { if (env) await env.cleanup(); });

test('[rules terms] consent is private, versioned, server-timed and immutable', async () => {
  const version = '2026-09-24';
  const path = `users/owner/legal_acceptances/${version}`;
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(), path)));
  const own = doc(client('owner'), path);
  const agreement = () => ({termsVersion: version, acceptedAt: serverTimestamp()});
  await assertFails(setDoc(doc(client('other'), path), agreement()));
  await assertFails(setDoc(own, {...agreement(), acceptedAt: Timestamp.fromMillis(0)}));
  await assertFails(setDoc(own, {...agreement(), unexpected: true}));
  await assertFails(setDoc(doc(client('owner'), 'users/owner/legal_acceptances/unknown'), {
    termsVersion: 'unknown', acceptedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(own, agreement()));
  const first = await assertSucceeds(getDoc(own));
  assert.equal(first.data().termsVersion, version);
  assert.ok(first.data().acceptedAt instanceof Timestamp);
  for (const context of [client('other'), client('admin'), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(context, path)));
  }
  await assertFails(updateDoc(own, {acceptedAt: serverTimestamp()}));
  await assertFails(deleteDoc(own));
  // A retry reads the existing record, without replacing its original timestamp.
  const db = client('owner');
  await assertSucceeds(runTransaction(db, async transaction => {
    const ref = doc(db, path);
    const existing = await transaction.get(ref);
    if (existing.data()?.termsVersion === version) return;
    transaction.set(ref, agreement());
  }));
  const afterRetry = await getDoc(own);
  assert.ok(first.data().acceptedAt.isEqual(afterRetry.data().acceptedAt));
});

test('[rules terms] old clients cannot publish until consent is saved', async () => {
  const db = client('owner');
  const path = 'users/owner/legal_acceptances/2026-09-24';
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(), path)));
  await assertSucceeds(getDoc(doc(db, 'users/owner')));
  await assertFails(setDoc(doc(db, 'spots/no-consent'), spot()));
  await assertSucceeds(setDoc(doc(db, path), {termsVersion: '2026-09-24', acceptedAt: serverTimestamp()}));
  await assertSucceeds(setDoc(doc(db, 'spots/with-consent'), spot()));
});

test('[rules XP config] achievement flag is optional, boolean and admin-only', async () => {
  const config = {levels_enabled: true, xp_awards_enabled: true, weeklyLimit: 3000,
    timezone: 'Europe/Riga', rulesVersion: 'ccs-xp-v1.0', updatedAt: serverTimestamp()};
  const ref = doc(client('admin'), 'app_config/xp');
  await assertSucceeds(setDoc(ref, config));
  await assertSucceeds(setDoc(ref, {...config, achievements_enabled: true}));
  await assertSucceeds(setDoc(ref, {...config, achievements_enabled: false}));
  await assertFails(setDoc(ref, {...config, achievements_enabled: 'true'}));
  await assertFails(setDoc(ref, {...config, achievements_enabled: true, weeklyLimit: 3001}));
  await assertFails(setDoc(doc(client('owner'), 'app_config/xp'), {...config, achievements_enabled: true}));
});

test('[rules XP] owner reads own stats, outsider cannot, no client can write XP', async () => {
  await seed({ 'xp_user_stats/owner': { userId: 'owner', xpTotal: 50 } });
  await assertSucceeds(getDoc(doc(client('owner'), 'xp_user_stats/owner')));
  await assertFails(getDoc(doc(client('other'), 'xp_user_stats/owner')));
  for (const uid of ['owner', 'mod', 'admin']) {
    await assertFails(updateDoc(doc(client(uid), 'xp_user_stats/owner'), { xpTotal: 9999 }));
    await assertFails(setDoc(doc(client(uid), 'xp_transactions/forged'), { userId: uid, amount: 9999 }));
  }
});

test('[rules badges] badge is readable without exposing XP, but cannot be forged', async () => {
  await seed({'xp_featured_achievements/owner': {item: {id: 'spots.1'}}});
  await assertSucceeds(getDoc(doc(client('other'), 'xp_featured_achievements/owner')));
  for (const uid of ['owner', 'other', 'admin', 'banned']) {
    await assertFails(setDoc(doc(client(uid), 'xp_featured_achievements/owner'), {item: {id: 'spots.50'}}));
  }
  await assertFails(getDoc(doc(client('banned'), 'xp_featured_achievements/owner')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'xp_featured_achievements/owner')));
});

test('[rules badges] private or blocked users cannot expose their badge to another account', async () => {
  for (const fields of [{publicProfile: false}, {settings: {publicProfile: false}}, {blockedUserIds: ['other']}]) {
    await seed({'users/owner': {role: 'user', ...fields}, 'xp_featured_achievements/owner': {item: {id: 'spots.1'}}});
    await assertFails(getDoc(doc(client('other'), 'xp_featured_achievements/owner')));
    await assertSucceeds(getDoc(doc(client('owner'), 'xp_featured_achievements/owner')));
  }
});

test('[rules spots] user creates pending spot but cannot self-approve or forge author', async () => {
  await assertSucceeds(setDoc(doc(client('owner'), 'spots/new'), spot()));
  await assertFails(setDoc(doc(client('owner'), 'spots/approved'), spot('owner', 'approved')));
  await assertFails(setDoc(doc(client('owner'), 'spots/forged'), spot('other')));
  await assertFails(setDoc(doc(client('banned'), 'spots/banned'), spot('banned')));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'spots/anon'), spot()));
});

test('[rules uploads] reserved draft spot cannot be claimed by a different user', async () => {
  await seed({'media_spot_reservations/draft': {uid: 'owner'}});
  await assertFails(setDoc(doc(client('other'), 'spots/draft'), spot('other')));
  await assertSucceeds(setDoc(doc(client('owner'), 'spots/draft'), spot()));
});

test('[rules deletion] new quotes cannot resurrect a deleting or missing source', async () => {
  await seed({'chats/test': {isGroup: true, memberIds: ['owner', 'other']},
    'chats/test/messages/source': {senderUid: 'owner', senderUsername: 'owner', text: 'source'}});
  const quote = {senderUid: 'other', senderUsername: 'other', text: 'reply',
    replyToMessageId: 'source', replyToText: 'source', replyToUsername: 'owner'};
  await assertSucceeds(setDoc(doc(client('other'), 'chats/test/messages/before'), quote));
  await seed({'account_deletions/owner': {status: 'queued'}});
  await assertFails(setDoc(doc(client('other'), 'chats/test/messages/during'), quote));
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(), 'chats/test/messages/source')));
  await assertFails(setDoc(doc(client('other'), 'chats/test/messages/after'), quote));
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

test('[rules spots] optional region config preserves country bans', async () => {
  await seed({'app_config/main': {bannedCountryCodes: ['LV']}});
  await assertFails(setDoc(doc(client('owner'), 'spots/blocked-code'), spot()));
  await seed({'app_config/main': {bannedCountryKeys: ['lv']}});
  await assertFails(setDoc(doc(client('owner'), 'spots/blocked-key'), spot()));
  await seed({'app_config/main': {bannedCountryCodes: [], bannedCountryKeys: []}});
  await assertSucceeds(setDoc(doc(client('owner'), 'spots/allowed'), spot()));
});

test('[rules groups] descriptions required and only actual non-banned members can message',async()=>{
  const group={isGroup:true,isPrivate:false,ownerUid:'owner',memberIds:['owner','other'],memberUsernames:['owner','other'],moderatorIds:[]};
  for(const description of ['', '   ', 'x'.repeat(1001)]) await assertFails(setDoc(doc(client('owner'),'chats/new'),{...group,description}));
  await assertSucceeds(setDoc(doc(client('owner'),'chats/new'),{...group,description:'First line\nSecond line'}));
  const msg=uid=>({senderUid:uid,senderUsername:uid,text:'Hello'});
  await assertSucceeds(setDoc(doc(client('other'),'chats/new/messages/member'),msg('other')));
  await assertFails(setDoc(doc(client('admin'),'chats/new/messages/nonmember'),msg('admin')));
  await seed({'chats/new':{...group,description:'Group',bannedMemberIds:['other']}});
  await assertFails(setDoc(doc(client('other'),'chats/new/messages/blocked'),msg('other')));
  await seed({'chats/new':{...group,memberIds:['owner'],memberUsernames:['owner'],description:'Group',bannedMemberIds:['other']}});
  await assertFails(updateDoc(doc(client('owner'),'chats/new'),{memberIds:['owner','other'],memberUsernames:['owner','other']}));
});

test('[rules moderation] bans and missing consent block direct/group message mutations', async () => {
  const group = {isGroup: true, memberIds: ['owner', 'banned'], description: 'Test'};
  const message = {senderUid: 'banned', senderUsername: 'banned', text: 'original'};
  await seed({'chats/test': group, 'chats/test/messages/existing': message});
  await assertFails(setDoc(doc(client('banned'), 'chats/test/messages/new'), message));
  await assertFails(updateDoc(doc(client('banned'), 'chats/test/messages/existing'), {text: 'edited'}));
  await env.withSecurityRulesDisabled(context => deleteDoc(doc(context.firestore(), 'users/owner/legal_acceptances/2026-09-24')));
  await assertFails(setDoc(doc(client('owner'), 'chats/test/messages/no-consent'), {...message, senderUid: 'owner'}));
  await assertFails(updateDoc(doc(client('owner'), 'chats/test'), {lastMessage: 'bypass'}));
});

test('[rules moderation] a block prevents direct sends and edits in both directions', async () => {
  await seed({
    'users/owner': {role: 'user', blockedUserIds: ['other']},
    'chats/direct': {isGroup: false, memberIds: ['owner', 'other']},
    'chats/direct/messages/owner': {senderUid: 'owner', senderUsername: 'owner', text: 'old'},
    'chats/direct/messages/other': {senderUid: 'other', senderUsername: 'other', text: 'old'},
  });
  for (const uid of ['owner', 'other']) {
    await assertFails(setDoc(doc(client(uid), `chats/direct/messages/new-${uid}`), {senderUid: uid, senderUsername: uid, text: 'new'}));
    await assertFails(updateDoc(doc(client(uid), `chats/direct/messages/${uid}`), {text: 'edit'}));
  }
});
