const test=require('node:test'), assert=require('node:assert/strict');
const {fixture}=require('./support');
const {buildXpTransactionId}=require('../lib/xp/xp-engine');
test('only admins can view recipients and the XP journal',async()=>{
 const f=fixture({'users/mod':{role:'moderator'},'users/admin':{role:'admin'}}), a=f.load('../lib/xp/admin-rewards.js');
 for(const uid of ['tester','mod','missing']) {
  await assert.rejects(a.recipients(uid,'r'));await assert.rejects(a.xpAudit(uid));
 }
 assert.equal((await a.xpAudit('admin')).items.length,0);
});
test('recipients distinguish paid, pending and unprocessed claims with pagination',async()=>{
 const rows={'users/admin':{role:'admin'}};
 for(let i=0;i<27;i++) {
  rows['users/u'+i]={username:'Driver'+i,email:'private@example.invalid'};
  rows['admin_reward_claims/c'+String(i).padStart(2,'0')]={userId:'u'+i,rewardId:'r',xp:200,completedAt:1000+i};
 }
 const input={userId:'u0',action:'admin_reward.completed',objectType:'admin_reward',objectId:'r',stage:'completed',amount:200};
 rows['xp_transactions/'+buildXpTransactionId(input)]={...input,status:'confirmed'};
 rows['xp_transactions/'+buildXpTransactionId({...input,userId:'u1'})]={...input,userId:'u1',status:'pending',amount:0};
 const f=fixture(rows),a=f.load('../lib/xp/admin-rewards.js');
 const first=await a.recipients('admin','r');assert.equal(first.items.length,25);
 assert.equal(first.items[0].receivedXp,200);assert.equal(first.items[1].status,'pending');assert.equal(first.items[2].status,'awaiting_payment');
 assert.equal(JSON.stringify(first).includes('private@example'),false);
 const second=await a.recipients('admin','r',first.nextCursor);assert.equal(second.items.length,2);assert.equal(second.nextCursor,null);
 await assert.rejects(a.recipients('admin','other',first.nextCursor));
});
test('journal exposes relevant ledger fields without private metadata',async()=>{
 const f=fixture({'users/admin':{role:'admin'},'xp_transactions/a':{userId:'tester',action:'visit.weekly',status:'confirmed',amount:50,requestedAmount:50,createdAt:123,metadata:{reason:'Weekly spot visit',secret:'hidden'}}});
 const result=await f.load('../lib/xp/admin-rewards.js').xpAudit('admin');
 assert.equal(result.items[0].amount,50);assert.equal(result.items[0].createdAt,123);assert.equal(JSON.stringify(result).includes('hidden'),false);
});
test('same-named target options include photo, city and coordinates',async()=>{
 const f=fixture({'users/admin':{role:'admin'},'spots/a':{name:'Same',status:'approved',cityCountry:'Riga',photoUrl:'https://example.invalid/a.jpg',lat:56,lng:24},'spots/b':{name:'Same',status:'approved',cityCountry:'Liepaja',lat:57,lng:25}});
 const a=f.load('../lib/xp/admin-rewards.js');const result=await a.targetOptions('admin','Same');
 assert.equal(result.items.length,2);assert.equal(result.items[0].cityCountry,'Riga');assert.equal(result.items[1].lat,57);
 assert.equal((await a.targetOptions('admin','Liepaja')).items[0].id,'b');
});
