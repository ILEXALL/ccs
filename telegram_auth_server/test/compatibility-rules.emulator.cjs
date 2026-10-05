const {test, before, beforeEach, after} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, serverTimestamp, arrayUnion, setLogLevel} = require('firebase/firestore');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw Error('Local emulator required');
setLogLevel('silent');
let env;
const client = uid => env.authenticatedContext(uid).firestore();
before(async () => {env = await initializeTestEnvironment({projectId:'demo-ccs-tests',firestore:{host:'127.0.0.1',port:18080,
  rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.compat.rules'),'utf8')}});});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    for (const uid of ['legacy','updated']) {
      await setDoc(doc(context.firestore(),`usernames/${uid}`),{uid,username:uid,usernameKey:uid});
    }
  });
});
after(async () => {await env?.cleanup();});
const profile = uid => ({uid,username:uid,usernameKey:uid,name:uid,role:'user'});

test('legacy profile creation, email/token writes and spot creation continue working', async () => {
  const db=client('legacy');
  await assertSucceeds(setDoc(doc(db,'users/legacy'),{...profile('legacy'),email:'synthetic@example.invalid'}));
  await assertSucceeds(updateDoc(doc(db,'users/legacy'),{fcmTokens:arrayUnion('synthetic-old-token'),fcmTokenUpdatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(db,'users/legacy'),{name:'Edited legacy profile'}));
  await assertSucceeds(setDoc(doc(db,'spots/legacy'),{addedByUid:'legacy',name:'Synthetic spot',cityCountry:'Riga, Latvia',countryCode:'LV',categories:['Photo'],status:'pending',rating:0}));
});

test('updated profile without public email and private account fields work; other users remain denied',async()=>{
  const db=client('updated');
  await assertSucceeds(setDoc(doc(db,'users/updated'),profile('updated')));
  await assertSucceeds(setDoc(doc(db,'users/updated/private/account'),{email:'synthetic@example.invalid',fcmTokens:['synthetic-new-token']}));
  await assertSucceeds(updateDoc(doc(db,'users/updated'),{name:'Edited new profile'}));
  await assertSucceeds(getDoc(doc(client('legacy'),'users/updated')));
  await assertFails(getDoc(doc(client('legacy'),'users/updated/private/account')));
  await assertFails(updateDoc(doc(client('legacy'),'users/updated/private/account'),{email:'forged'}));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'users/updated/private/account')));
});

test('consent remains versioned, immutable and private during transition',async()=>{
  const db=client('updated');
  const ref=doc(db,'users/updated/legal_acceptances/2026-09-24');
  await assertSucceeds(setDoc(ref,{termsVersion:'2026-09-24',acceptedAt:serverTimestamp()}));
  await assertSucceeds(getDoc(ref));
  await assertFails(getDoc(doc(client('legacy'),'users/updated/legal_acceptances/2026-09-24')));
  await assertFails(updateDoc(ref,{acceptedAt:serverTimestamp()}));
});
