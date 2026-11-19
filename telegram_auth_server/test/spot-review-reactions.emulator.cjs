const {test,before,beforeEach,after}=require('node:test');
const fs=require('node:fs');const path=require('node:path');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,deleteField,setLogLevel}=require('firebase/firestore');
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:18080')throw Error('Local emulator required');
setLogLevel('silent');let env;
const db=uid=>uid?env.authenticatedContext(uid).firestore():env.unauthenticatedContext().firestore();
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-ccs-reactions',firestore:{host:'127.0.0.1',port:18080,rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.rules'),'utf8')}})});
beforeEach(async()=>{await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
for(const uid of ['owner','alice','bob','banned'])await setDoc(doc(c.firestore(),'users/'+uid),{uid,username:uid,role:'user',banned:uid==='banned'});
await setDoc(doc(c.firestore(),'spots/public'),{visibility:'public',addedByUid:'owner'});
await setDoc(doc(c.firestore(),'spots/private'),{visibility:'group',sharedGroupIds:['secret'],addedByUid:'owner'});
await setDoc(doc(c.firestore(),'spot_reviews/review'),{spotId:'public',userId:'owner',username:'owner',comment:'hello'});
await setDoc(doc(c.firestore(),'spot_reviews/private'),{spotId:'private',userId:'owner',username:'owner',comment:'secret'});
})});after(async()=>env?.cleanup());
test('add, replace, remove and concurrent users retain independent persisted reactions',async()=>{
const a=doc(db('alice'),'spot_reviews/review'),b=doc(db('bob'),'spot_reviews/review');
await Promise.all([assertSucceeds(updateDoc(a,{'reactions.alice':'❤️'})),assertSucceeds(updateDoc(b,{'reactions.bob':'🔥'}))]);
await assertSucceeds(updateDoc(a,{'reactions.alice':'👍'}));
let data=(await getDoc(a)).data();require('node:assert/strict').deepEqual(data.reactions,{alice:'👍',bob:'🔥'});
await assertSucceeds(updateDoc(a,{'reactions.alice':deleteField()}));
require('node:assert/strict').deepEqual((await getDoc(b)).data().reactions,{bob:'🔥'});
});
test('cannot forge others reactions, alter comment, replace map, or write invalid values',async()=>{
const a=doc(db('alice'),'spot_reviews/review');
await assertSucceeds(updateDoc(doc(db('bob'),'spot_reviews/review'),{'reactions.bob':'🔥'}));
for(const change of [{'reactions.bob':'👍'},{reactions:{alice:'👍'}},{'reactions.alice':42},{'reactions.alice':''},{'reactions.alice':'x'.repeat(33)},{'reactions.alice':'👍',comment:'forged'},{'reactions.alice':'👍',spotId:'private'}])await assertFails(updateDoc(a,change));
await assertFails(updateDoc(doc(db('owner'),'spot_reviews/review'),{'reactions.bob':deleteField()}));
await assertSucceeds(updateDoc(doc(db('owner'),'spot_reviews/review'),{comment:'edited'}));
});
test('anonymous, banned and private-event outsiders cannot react',async()=>{
for(const uid of [null,'banned'])await assertFails(updateDoc(doc(db(uid),'spot_reviews/review'),{['reactions.'+(uid||'anon')]:'👍'}));
await assertFails(updateDoc(doc(db('alice'),'spot_reviews/private'),{'reactions.alice':'👍'}));
});
test('new comments cannot seed forged reactions; legacy empty field is compatible',async()=>{
const base={spotId:'public',userId:'alice',username:'alice',comment:'new',type:'comment'};
await assertSucceeds(setDoc(doc(db('alice'),'spot_reviews/new'),base));
await assertSucceeds(setDoc(doc(db('alice'),'spot_reviews/empty'),{...base,reactions:{}}));
await assertFails(setDoc(doc(db('alice'),'spot_reviews/forged'),{...base,reactions:{bob:'👍'}}));
});
