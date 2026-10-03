const {test, after} = require('node:test');
const assert = require('node:assert/strict');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080') throw new Error('Local emulator required');
const admin = require('firebase-admin');
admin.initializeApp({projectId: 'demo-ccs-tests'});
const {grantXp} = require('../lib/xp/admin-grants');
const db = admin.firestore();
after(()=>admin.app().delete());
test('concurrent duplicate grants commit once; independent grants preserve both balances',async()=>{
  const uid='grant-recipient';
  await db.doc('users/grant-admin').set({role:'admin'});
  await db.doc(`users/${uid}`).set({username:'GrantDriver'});
  await db.doc('usernames/grantdriver').set({uid});
  await db.doc(`xp_user_stats/${uid}`).set({xpTotal:7796,level:18,weeklyXp:325,weeklyConsumedXp:200});
  const input={userId:uid,username:'GrantDriver',amount:1000,reason:'Community support',requestId:'emulator-grant-duplicate'};
  const results=await Promise.all([grantXp('grant-admin',input),grantXp('grant-admin',input)]);
  assert.equal(results.filter(r=>!r.duplicate).length,1);
  assert.equal((await db.doc(`xp_user_stats/${uid}`).get()).data().xpTotal,8796);
  await Promise.all([grantXp('grant-admin',{...input,amount:100,requestId:'independent-one'}),
    grantXp('grant-admin',{...input,amount:200,requestId:'independent-two'})]);
  const stats=(await db.doc(`xp_user_stats/${uid}`).get()).data();
  assert.equal(stats.xpTotal,9096); assert.equal(stats.level,20);
  assert.equal(stats.weeklyXp,325); assert.equal(stats.weeklyConsumedXp,200);
  assert.equal((await db.collection('xp_transactions').where('userId','==',uid).get()).size,3);
  assert.equal((await db.collection('xp_admin_audit').where('userId','==',uid).get()).size,3);
});
