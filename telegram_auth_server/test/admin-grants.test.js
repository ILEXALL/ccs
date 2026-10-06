const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
function setup(extra = {}) {
  const f = fixture({'users/admin': {role: 'admin'},
    'users/tester': {username: 'Driver'}, 'usernames/driver': {uid: 'tester'},
    'xp_user_stats/tester': {xpTotal: 7796, level: 18, weeklyXp: 325}, ...extra});
  return {...f, ...f.load('../lib/xp/admin-grants.js')};
}
const input = {username: 'Driver', userId: 'tester', amount: 1000,
  requestId: 'test-grant-001', reason: 'Helped the community'};
test('grant updates lifetime XP and level, records the reason, and retries once', async () => {
  const f = setup();
  assert.deepEqual(JSON.parse(JSON.stringify(await f.grantTarget('admin', {username: '@DRIVER'}))), {userId:'tester', username:'Driver'});
  const result = await f.grantXp('admin', input);
  assert.equal(result.xpTotal, 8796); assert.equal(result.level, 19);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp, 325);
  const ledger = f.rows.get('xp_transactions/' + result.transactionId);
  assert.equal(ledger.action, 'admin.grant');
  assert.equal(ledger.status, 'confirmed');
  assert.equal(ledger.amount, 1000);
  assert.ok(ledger.createdAt);
  const {publicHistory} = require('../lib/xp/history');
  assert.equal(publicHistory([ledger], new Map(), new Set()).items[0].amount, 1000);
  assert.equal(ledger.reason, input.reason); assert.equal(ledger.metadata.reason, input.reason);
  assert.equal(ledger.historicalCatchup, true); assert.equal(ledger.weekKey, null);
  assert.equal((await f.grantXp('admin', input)).duplicate, true);
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal, 8796);
  assert.equal([...f.rows.keys()].filter(k=>k.startsWith('xp_admin_audit/')).length, 1);
  for (const changed of [{amount:999}, {reason:'Different'}, {userId:'other'}]) {
    await assert.rejects(f.grantXp('admin', {...input,...changed}), /already used/);
  }
});
test('non-admins, banned/deleted admins, and self grants cannot write', async () => {
  for (const actor of [{role:'moderator'}, {role:'admin',banned:true}, {role:'admin',deleted:true}]) {
    const f = setup({'users/admin':actor});
    await assert.rejects(f.grantXp('admin',input),/Admin/);
    await assert.rejects(f.grantTarget('admin',input),/Admin/);
    assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,7796);
  }
  const f=setup({'users/tester':{role:'admin',username:'Driver'}});
  await assert.rejects(f.grantXp('tester',input),/yourself/);
});
test('rejects deleted/blocked recipients, invalid amounts, missing reasons and changed usernames',async()=>{
  for(const field of ['deleted','banned','xpBlocked']) {
    const f=setup({'users/tester':{username:'Driver',[field]:true}});
    assert.equal((await f.grantRequest(f.grantXp,'admin',input)).rejected,true);
    assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,7796);
  }
  const f=setup({'account_deletions/tester':{status:'processing'}});
  await assert.rejects(f.grantXp('admin',input),/deleted/);
  for(const amount of [0,-1,3001,1.5,'1000',NaN]) await assert.rejects(setup().grantXp('admin',{...input,amount}));
  for(const reason of ['', ' ', 'a'.repeat(501)]) await assert.rejects(setup().grantXp('admin',{...input,reason}));
  await assert.rejects(setup({'usernames/driver':{uid:'other'}}).grantXp('admin',input),/changed/);
  await assert.rejects(setup({'users/tester':{username:'Renamed'}}).grantXp('admin',input),/changed/);
});
test('retry stays tied to original award after recipient rename; unknown failures are not declared rejected', async()=>{
  const f=setup(); await f.grantXp('admin',input);
  f.rows.set('usernames/driver',{uid:'other'});
  assert.equal((await f.grantXp('admin',input)).duplicate,true);
  await assert.rejects(f.grantRequest(async()=>{throw new Error('network');},'admin',input),/network/);
});
test('admin grants can be revoked/restored without affecting weekly XP', async()=>{
  const f=setup(); const result=await f.grantXp('admin',input);
  const {adjustXp}=f.load('../lib/xp/xp-adjustments.js');
  const adjustment={transactionId:result.transactionId,requestId:'revoke-1',reason:'Correction',operation:'revoke',expectedRevision:0};
  assert.equal((await adjustXp('admin',adjustment)).xpTotal,7796);
  assert.equal((await adjustXp('admin',{...adjustment,requestId:'restore-1',operation:'restore',expectedRevision:1})).xpTotal,8796);
  assert.equal(f.rows.get('xp_user_stats/tester').weeklyXp,325);
});
