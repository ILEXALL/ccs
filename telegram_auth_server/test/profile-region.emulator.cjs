const {test,before,after}=require('node:test');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,runTransaction,serverTimestamp,setLogLevel}=require('firebase/firestore');
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:18080')throw Error('Local emulator required');
setLogLevel('silent');let env;
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-ccs-region',firestore:{host:'127.0.0.1',port:18080,rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.rules'),'utf8')}});await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
 for(const uid of ['new','existing','legacy','banned','legacy-tokens'])await setDoc(doc(c.firestore(),'users/'+uid),{uid,username:uid,role:'user',city:uid==='existing'?'Riga':'',country:uid==='existing'?'Latvia':'',banned:uid==='banned',...(uid==='legacy'||uid==='banned'?{email:'synthetic@example.invalid'}:{}),...(uid==='legacy-tokens'?{fcmTokens:['synthetic-old-token'],lastFcmTokenPlatform:'android',fcmTokenUpdatedAt:new Date(0)}:{})});
});});after(async()=>env?.cleanup());
const save=uid=>{const db=env.authenticatedContext(uid).firestore();return runTransaction(db,async tx=>{const ref=doc(db,'users/'+uid);await tx.get(ref);tx.update(ref,{city:'Kyiv',country:'Ukraine',updatedAt:serverTimestamp()});});};
test('new and existing active owners may save their region transactionally',async()=>{await assertSucceeds(save('new'));await assertSucceeds(save('existing'));});
test('legacy profile fields do not block region updates from existing installed builds',async()=>{
 await assertSucceeds(save('legacy'));
 await assertSucceeds(save('legacy-tokens'));
 const ref=doc(env.authenticatedContext('legacy').firestore(),'users/legacy');
 // The previous app uses updateDoc rather than a transaction.
 await assertSucceeds(updateDoc(ref,{city:'Riga',country:'Latvia',updatedAt:serverTimestamp()}));
 await assertSucceeds(setDoc(ref,{name:'Driver',provider:'google',updatedAt:serverTimestamp()},{merge:true}));
});

test('compatibility cannot publish new secrets or change existing legacy secrets',async()=>{
 const db=env.authenticatedContext('legacy').firestore(),ref=doc(db,'users/legacy');
 await assertFails(updateDoc(ref,{city:'Riga',email:'changed@example.invalid'}));
 await assertFails(updateDoc(ref,{fcmTokens:['synthetic-token']}));
 await assertFails(updateDoc(doc(env.authenticatedContext('new').firestore(),'users/new'),{email:'new@example.invalid'}));
 await assertFails(updateDoc(ref,{city:'Riga',role:'admin'}));
 await assertFails(updateDoc(ref,{city:'Riga',moderatorCountryCodes:['LV']}));
 const tokenRef=doc(env.authenticatedContext('legacy-tokens').firestore(),'users/legacy-tokens');
 await assertFails(updateDoc(tokenRef,{fcmTokens:['replacement-token']}));
 await assertFails(updateDoc(tokenRef,{fcmTokenUpdatedAt:serverTimestamp()}));
 await assertFails(updateDoc(tokenRef,{lastFcmTokenPlatform:'ios'}));
 await assertFails(updateDoc(doc(env.unauthenticatedContext().firestore(),'users/legacy'),{city:'Riga',country:'Latvia'}));
});
test('foreign users and banned profiles cannot use region saves to bypass access',async()=>{
 await assertFails(save('banned'));
 await assertFails(updateDoc(doc(env.authenticatedContext('new').firestore(),'users/existing'),{city:'forged',country:'Latvia'}));
 await assertFails(updateDoc(doc(env.authenticatedContext('new').firestore(),'users/new'),{city:'Riga',country:'Latvia',role:'admin'}));
});
