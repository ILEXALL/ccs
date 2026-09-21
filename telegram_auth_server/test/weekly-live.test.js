const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture, completedDwell} = require('./support');
const now = Date.parse('2026-09-22T12:00:00Z');
const gps = at => ({latitude:0, longitude:0, accuracy:10, isMocked:false, recordedAtMillis:at});
function setup() { return fixture({'users/admin':{role:'admin'}, 'users/mod':{role:'moderator'},
  'users/tester':{role:'user'}, 'spots/s':{status:'approved',lat:0,lng:0,name:'Spot',category:'photo'},
  'app_config/xp':{levels_enabled:true,xp_awards_enabled:true,achievements_enabled:true,enabledUserIds:['*'],weeklyLimit:3000,timezone:'Europe/Riga'}}); }
function campaign(id='campaign') { return {id, spotId:'s',title:{en:'Visit',ru:'Посети',lv:'Apmeklē'},xp:250,startsAt:now,endsAt:now+86400000}; }
async function visit(f, spot='s', time=now) { completedDwell(f,'tester',spot,time); return f.load('../lib/spot-visits.js').recordSpotVisit(f.db,'tester',spot,time,gps(time)); }
test('520 weeks: stable schedule, 600 XP, no adjacent metric repeats or IDs within four weeks', () => {
  const service=setup().load('../lib/xp/weekly-tasks.js'); const history=[];
  for(let i=0;i<520;i++) {
    const key=new Date(Date.parse('2026-09-21')+i*604800000).toISOString().slice(0,10);
    const tasks=service.tasksForWeek(key);
    assert.equal(tasks.reduce((n,t)=>n+t.xp,0),600);
    for(const t of tasks) {
      assert.ok(!history.slice(-3).flat().some(old=>old.id===t.id));
      assert.ok(!(history.at(-1)||[]).some(old=>old.metric===t.metric));
    }
    assert.deepEqual(service.tasksForWeek(key), tasks); history.push(tasks);
  }
});
test('admin-only writes, input validation and immutable idempotent create', async()=>{
  const f=setup(), a=f.load('../lib/xp/admin-rewards.js');
  for(const uid of ['tester','mod','missing']) {
    await assert.rejects(a.createReward(uid,campaign(),now));
    await assert.rejects(a.listRewards(uid));
    await assert.rejects(a.targetOptions(uid));
    await assert.rejects(a.cancelReward(uid,'campaign',now));
  }
  for(const xp of [-1,0,3001,1.5]) await assert.rejects(a.createReward('admin',{...campaign(),xp},now));
  await a.createReward('admin',campaign(),now);await a.createReward('admin',campaign(),now);
  await assert.rejects(a.createReward('admin',{...campaign(),xp:900},now));
  assert.equal(f.rows.get('admin_rewards/campaign').xp,250);
});
test('repeat GPS cannot duplicate XP; same spot earns again next week without repeating lifetime achievement', async()=>{
  const f=setup(), w=f.load('../lib/xp/weekly-tasks.js');
  await visit(f);await w.syncWeeklyTasks('tester',{now:new Date(now)});
  await visit(f);await w.syncWeeklyTasks('tester',{now:new Date(now)});
  assert.equal([...f.rows.values()].filter(r=>r.action==='visit.weekly').length,1);
  await visit(f,'s',now+604800000);await w.syncWeeklyTasks('tester',{now:new Date(now+604800000)});
  assert.equal([...f.rows.values()].filter(r=>r.action==='visit.weekly').length,2);
  assert.equal([...f.rows.keys()].filter(k=>k.startsWith('spot_visit_records/')).length,1);
});
test('admin reward requires fresh eligible visit, survives cancellation and cap, settles once next week',async()=>{
  const f=setup(), a=f.load('../lib/xp/admin-rewards.js'), w=f.load('../lib/xp/weekly-tasks.js');
  await visit(f,'s',now-1000);
  await a.createReward('admin',campaign(),now);
  await w.syncWeeklyTasks('tester',{now:new Date(now)});
  assert.equal([...f.rows.values()].filter(r=>r.action==='admin_reward.completed').length,0);
  f.rows.set('xp_user_weeks/tester_2026-09-21',{confirmedXp:3000});
  f.rows.set('xp_user_stats/tester',{xpTotal:3000});
  await visit(f); await a.cancelReward('admin','campaign',now+1);
  await w.syncWeeklyTasks('tester',{now:new Date(now+2)});
  const entry=()=>[...f.rows.values()].find(r=>r.action==='admin_reward.completed');
  assert.equal(entry().status,'pending'); assert.equal(entry().requestedAmount,250);
  await w.syncWeeklyTasks('tester',{now:new Date(now+604800000)});
  assert.equal(entry().status,'confirmed'); assert.equal(entry().amount,250);
  const total=f.rows.get('xp_user_stats/tester').xpTotal;
  await w.syncWeeklyTasks('tester',{now:new Date(now+604800000)});
  assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,total);
});
test('expired, cancelled, future and inaccessible targets never award or leak', async()=>{
  const f=setup(), a=f.load('../lib/xp/admin-rewards.js'), w=f.load('../lib/xp/weekly-tasks.js');
  await a.createReward('admin',campaign(),now);
  await visit(f,'s',now+86400000);
  assert.equal([...f.rows.keys()].filter(k=>k.startsWith('admin_reward_claims/')).length,0);
  f.rows.get('spots/s').visibility='group';f.rows.get('spots/s').sharedGroupIds=['private'];
  await assert.rejects(visit(f));
  assert.equal((await w.weeklyProgress('tester',{now:new Date(now),sync:false})).adminItems.length,0);
});
test('seven weekly paid spots maximum; eighth can still advance tasks', async()=>{
  const f=setup(), w=f.load('../lib/xp/weekly-tasks.js');
  for(let i=0;i<8;i++){f.rows.set('spots/s'+i,{status:'approved',lat:0,lng:0});await visit(f,'s'+i,now+Math.floor(i/3)*86400000+i);}
  await w.syncWeeklyTasks('tester',{now:new Date(now+3*86400000)});
  assert.equal([...f.rows.values()].filter(r=>r.action==='visit.weekly').length,7);
});
test('live weekly completion uses server visit evidence and awards exactly once', async()=>{
  const f=setup(), w=f.load('../lib/xp/weekly-tasks.js');
  const tasks=w.tasksForWeek('2026-09-21');
  // Supply verified visits via the actual recorder; no claimed client counters.
  for(let i=0;i<7;i++) {
    f.rows.set('spots/p'+i,{status:'approved',lat:0,lng:0,categories:[['Photo','Food','Activity'][i%3]],addedByUid:'other'});
    await visit(f,'p'+i,now+i*86400000/2);
  }
  const result=await w.weeklyProgress('tester',{now:new Date(now+3*86400000)});
  for(const task of result.items.filter(t=>t.progress>=t.target)) assert.ok(['confirmed','pending'].includes(task.status));
  assert.ok(result.items.some(t=>t.progress>=t.target));
  const before=JSON.stringify([...f.rows].filter(([k])=>k.startsWith('xp_transactions/')));
  await w.syncWeeklyTasks('tester',{now:new Date(now+3*86400000)});
  assert.equal(JSON.stringify([...f.rows].filter(([k])=>k.startsWith('xp_transactions/'))),before);
});
test('different-day tasks require distinct places, categories read the actual categories array',()=>{
  const w=setup().load('../lib/xp/weekly-tasks.js');
  const rows=[{spotId:'a',dayKey:'2026-09-21',categories:['Photo']},{spotId:'a',dayKey:'2026-09-22',categories:['Photo']},{spotId:'b',dayKey:'2026-09-23',categories:['Food']},{spotId:'c',dayKey:'2026-09-23',categories:['Activity']}];
  assert.equal(w.progress({metric:'distinct_visit_days',target:3},rows,[]),2);
  assert.equal(w.progress({metric:'visited_categories',target:3},rows,[]),3);
});
test('campaign boundaries, cancellation before arrival and private member access',async()=>{
  const f=setup(), a=f.load('../lib/xp/admin-rewards.js');
  await a.createReward('admin',campaign('cancel'),now);await a.cancelReward('admin','cancel',now);
  await a.createReward('admin',{...campaign('future'),startsAt:now+1000},now);
  await visit(f);assert.equal([...f.rows.keys()].filter(k=>k.startsWith('admin_reward_claims/')).length,0);
  await visit(f,'s',now+1000);assert.equal([...f.rows.values()].filter(r=>r.rewardId==='future').length,1);
  f.rows.set('spots/event',{status:'approved',lat:0,lng:0,isTemporary:true,startsAt:now,expiresAt:now+86400000,visibility:'group',sharedGroupIds:['g']});
  await a.createReward('admin',{...campaign('private'),spotId:'event'},now);
  await assert.rejects(visit(f,'event'));
  f.rows.set('chats/g',{isGroup:true,memberIds:['tester']});await visit(f,'event');
  assert.equal([...f.rows.values()].filter(r=>r.rewardId==='private').length,1);
});
test('public rewards reads do not mutate XP or disclose custom assignments',async()=>{
  const f=setup();f.rows.set('users/viewer',{});
  const before=JSON.stringify([...f.rows]);
  const result=await f.load('../lib/xp/public-profile.js').publicXpProfile('viewer','tester','rewards');
  assert.equal(result.weekly.status,'private');assert.equal(result.weekly.items.length,0);
  assert.equal(JSON.stringify([...f.rows]),before);
});
test('Riga Monday boundary creates independent weekly rewards; delayed processing preserves completed prior-week tasks',async()=>{
  const f=setup(), w=f.load('../lib/xp/weekly-tasks.js');
  const sunday=Date.parse('2026-09-27T20:59:59.999Z'), monday=sunday+1;
  await visit(f,'s',sunday);await visit(f,'s',monday);
  const rows=[...f.rows.entries()].filter(([k])=>k.startsWith('weekly_visit_records/')).map(([,r])=>r);
  assert.deepEqual(rows.map(r=>r.weekKey).sort(),['2026-09-21','2026-09-28']);
  await w.syncWeeklyTasks('tester',{now:new Date(monday)});
  assert.equal([...f.rows.values()].filter(r=>r.action==='visit.weekly').length,2);
});
test('campaign rejects non-overlapping event windows and extreme dates',async()=>{
  const f=setup(), a=f.load('../lib/xp/admin-rewards.js');
  f.rows.set('spots/e',{status:'approved',isTemporary:true,startsAt:now+10000,expiresAt:now+20000});
  await assert.rejects(a.createReward('admin',{...campaign(),spotId:'e',endsAt:now+9999},now));
  await assert.rejects(a.createReward('admin',{...campaign(),startsAt:1e16,endsAt:1e16+1000},now));
});

test('admin target browser paginates all approved places and searches beyond first page', async () => {
  const f = setup(), a = f.load('../lib/xp/admin-rewards.js');
  for (let i = 0; i < 12; i++) f.rows.set(`spots/place${i}`, {status: 'approved', name: `Place ${String(i).padStart(2, '0')}`});
  f.rows.set('spots/riga', {status: 'approved', name: 'Rīga Meet', isTemporary: true});
  f.rows.set('spots/deleted', {status: 'approved', name: 'Deleted', deleted: true});
  f.rows.set('spots/pending', {status: 'pending', name: 'Pending'});
  const ids = [];
  let offset = 0;
  do {
    const page = await a.targetOptions('admin', '', offset);
    assert.ok(page.items.length <= 5);
    ids.push(...page.items.map(item => item.id));
    offset = page.nextOffset;
  } while (offset !== null);
  assert.equal(ids.length, 14);
  assert.equal(new Set(ids).size, 14);
  assert.ok(!ids.includes('deleted') && !ids.includes('pending'));
  assert.deepEqual(JSON.parse(JSON.stringify((await a.targetOptions('admin', ' RIGA ')).items)), [{id: 'riga', name: 'Rīga Meet', event: true, cityCountry:'',photoUrl:'',lat:null,lng:null}]);
  assert.equal((await a.targetOptions('admin', 'Place 11')).items[0].id, 'place11');
  assert.equal((await a.targetOptions('admin', 'absent')).items.length, 0);
});

test('retired full car task is absent from both award evaluation and reward catalog', () => {
  const f = setup();
  const catalog = f.load('../lib/xp/rewards.js').rewardCatalog();
  assert.ok(!catalog.some(item => item.id === 'garage.first_car_full'));
  assert.equal(catalog.filter(item => item.category === 'garage_car').length, 4);
});
