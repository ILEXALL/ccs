const {test, before, beforeEach, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, updateDoc, setLogLevel} = require('firebase/firestore');
const {createSpot} = require('../lib/create-spot');
const {migratePrivateProfile, deliveryTokens, removeDeliveryTokens} = require('../lib/private-profile');
const {uploadPath, authorizeUpload} = require('../lib/upload-access');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw new Error('Local emulator required');
setLogLevel('silent');
const projectId = 'demo-ccs-tests';
const app = admin.initializeApp({projectId}, 'security-migration');
const db = app.firestore();
let env;
before(async () => { env = await initializeTestEnvironment({projectId, firestore:{host:'127.0.0.1',port:18080,
  rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.rules'),'utf8')}}); });
beforeEach(async () => {
  await env.clearFirestore();
  await db.doc('users/owner').set({uid:'owner',role:'user',username:'Owner',country:'Latvia'});
  await db.doc('users/other').set({uid:'other',role:'user'});
});
after(async () => { await env?.cleanup(); await app.delete(); });
const own = () => env.authenticatedContext('owner').firestore();
const request = (groups = []) => ({id:'test-spot',spot:{name:'Test',description:'Hello',countryCode:'LV',cityCountry:'Riga, Latvia',lat:56.9,lng:24.1,categories:['Photo'],photoUrls:[],sharedGroupIds:groups,visibility:groups.length?'group':'public',isTemporary:groups.length>0,startsAt:Date.now(),expiresAt:Date.now()+3600000}});
const consent = () => db.doc('users/owner/legal_acceptances/2026-09-24').set({termsVersion:'2026-09-24',acceptedAt:admin.firestore.Timestamp.now()});

test('private profile is owner-only and public profiles cannot receive secrets', async () => {
  const privatePath='users/owner/private/account';
  await assertSucceeds(setDoc(doc(own(), privatePath),{email:'test@example.invalid',fcmTokens:['synthetic']}));
  await assertSucceeds(getDoc(doc(own(),privatePath)));
  for (const context of [env.authenticatedContext('other'),env.authenticatedContext('admin'),env.unauthenticatedContext()]) {
    await assertFails(getDoc(doc(context.firestore(),privatePath)));
    await assertFails(setDoc(doc(context.firestore(),privatePath),{email:'forged'}));
  }
  await db.doc('users/admin').set({role:'admin'});
  for (const field of ['email','fcmTokens','fcmTokenUpdatedAt','lastFcmTokenPlatform']) {
    await assertFails(updateDoc(doc(env.authenticatedContext('admin').firestore(),'users/owner'),{[field]:'private'}));
  }
  await assertFails(setDoc(doc(own(),privatePath),{role:'admin'}));
  await assertSucceeds(getDoc(doc(env.authenticatedContext('other').firestore(),'users/owner')));
});

test('migration is dry-run by default, atomic, repeatable and preserves both token sources', async () => {
  const ref=db.doc('users/owner');
  await ref.update({email:'test@example.invalid',fcmTokens:['old']});
  await db.doc('users/owner/private/account').set({fcmTokens:['new']});
  assert.equal(await migratePrivateProfile(db,admin,ref),true);
  assert.equal((await ref.get()).data().email,'test@example.invalid');
  await migratePrivateProfile(db,admin,ref,true);
  const data=(await ref.get()).data();
  assert.equal(data.email,undefined); assert.equal(data.fcmTokens,undefined);
  assert.equal(data.username,'Owner');
  assert.deepEqual((await deliveryTokens(db,'owner')).sort(),['new','old']);
  assert.equal(await migratePrivateProfile(db,admin,ref,true),false);
  await removeDeliveryTokens(db,'owner',['old']);
  assert.deepEqual(await deliveryTokens(db,'owner'),['new']);
  assert.equal((await ref.get()).data().fcmTokens,undefined);
});

test('new profiles no longer need a public email and can still edit their display name', async () => {
  await db.doc('usernames/newuser').set({uid:'newuser',username:'newuser',usernameKey:'newuser'});
  const client=env.authenticatedContext('newuser').firestore();
  const ref=doc(client,'users/newuser');
  const data={uid:'newuser',username:'newuser',usernameKey:'newuser',name:'New user',role:'user'};
  await assertFails(setDoc(ref,{...data,email:'private@example.invalid'}));
  await assertSucceeds(setDoc(ref,data));
  await assertSucceeds(updateDoc(ref,{name:'Edited name'}));
  await assertSucceeds(setDoc(doc(client,'users/newuser/private/account'),{email:'private@example.invalid'}));
});

test('approval follows the staff country and banned users cannot create spots', async () => {
  await consent();
  await db.doc('users/owner').update({role:'moderator',moderatorCountryCodes:['EE']});
  assert.equal((await createSpot(db,admin,'owner',request(),'https://images.example.invalid')).status,'pending');
  await db.doc('users/owner').update({moderatorCountryCodes:['LV']});
  const input=request();input.id='regional-spot';
  assert.equal((await createSpot(db,admin,'owner',input,'https://images.example.invalid')).status,'approved');
  await db.doc('users/owner').update({banned:true});
  input.id='banned-spot';
  await assert.rejects(createSpot(db,admin,'owner',input,'https://images.example.invalid'),{status:403});
});

test('creation requires consent and cannot bypass server using Firestore', async () => {
  await assert.rejects(createSpot(db,admin,'owner',request(),'https://images.example.invalid'),{status:403});
  await consent();
  for (const uid of ['owner','admin']) await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(),'spots/bypass'),request().spot));
  const input=request(); input.spot.status='approved';input.spot.addedByUid='other'; input.spot.likeCount=999;
  await createSpot(db,admin,'owner',input,'https://images.example.invalid');
  const saved=(await db.doc('spots/test-spot').get()).data();
  assert.equal(saved.status,'pending');assert.equal(saved.addedByUid,'owner');assert.equal(saved.likeCount,0);
});

test('eight groups create atomically with canonical group data and a private topic; retry does not duplicate', async () => {
  await consent();
  const ids=Array.from({length:8},(_,i)=>`group${i}`);
  for (const id of ids) await db.doc(`chats/${id}`).set({isGroup:true,memberIds:['owner'],name:id});
  const input=request(ids);input.spot.sharedGroups=[{id:'forged',name:'Forged'}];
  await Promise.all([createSpot(db,admin,'owner',input,'https://images.example.invalid'),createSpot(db,admin,'owner',input,'https://images.example.invalid')]);
  const saved=(await db.doc('spots/test-spot').get()).data();assert.equal(saved.sharedGroups.length,8);
  for (const id of ids) assert.equal((await db.doc(`chats/${id}/spot_links/test-spot`).get()).data().published,false);
  const topic=(await db.doc('forum_topics/temporary_spot_test-spot').get()).data();assert.equal(topic.visibility,'group');assert.deepEqual(topic.sharedGroupIds,ids);
  await assert.rejects(createSpot(db,admin,'owner',{...input,spot:{...input.spot,name:'Changed'}},'https://images.example.invalid'),{status:409});
});

test('outsider groups, banned country, deleted accounts and foreign photo keys are denied', async () => {
  await consent();
  await db.doc('chats/outsider').set({isGroup:true,memberIds:['other']});
  await assert.rejects(createSpot(db,admin,'owner',request(['outsider']),'https://images.example.invalid'),{status:403});
  assert.equal((await db.doc('spots/test-spot').get()).exists,false);
  await db.doc('app_config/main').set({bannedCountryCodes:['LV']});
  await assert.rejects(createSpot(db,admin,'owner',request(),'https://images.example.invalid'),{status:403});
  await db.doc('app_config/main').delete();
  await db.doc('account_deletions/owner').set({status:'queued'});
  await assert.rejects(createSpot(db,admin,'owner',request(),'https://images.example.invalid'),{status:403});
  await db.doc('account_deletions/owner').delete();
  const input=request();input.spot.photoUrls=['https://images.example.invalid/users/other/spot_photos/test-spot/photo.jpg'];
  await assert.rejects(createSpot(db,admin,'owner',input,'https://images.example.invalid'),{status:400});
});

test('uploads reject traversal, unclaimed shared spot paths, other owners and deleting accounts', async () => {
  for (const value of ['users/owner/../other/a.jpg','/users/owner/a.jpg','users/owner//a.jpg','users/owner/%2e%2e/a.jpg']) assert.equal(uploadPath(value),null);
  assert.equal(uploadPath('users/owner/spot_photos/abc/photo_1.jpg'),'users/owner/spot_photos/abc/photo_1.jpg');
  assert.equal(await authorizeUpload(db,'owner','users/owner/avatar.jpg'),null);
  assert.ok(await authorizeUpload(db,'owner','users/other/avatar.jpg'));
  assert.ok(await authorizeUpload(db,'owner','spots/unclaimed/photo.jpg'));
  await db.doc('account_deletions/owner').set({status:'queued'});
  assert.ok(await authorizeUpload(db,'owner','users/owner/avatar.jpg'));
});
