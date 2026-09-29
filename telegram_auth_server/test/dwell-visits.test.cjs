const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');
const now = Date.parse('2026-09-22T12:00:00Z');
const fix = (time, lat = 56.9496) => ({latitude:lat, longitude:24.1052,accuracy:10,isMocked:false,recordedAtMillis:time});
function setup() {return fixture({'users/admin':{role:'admin'}, 'app_config/xp':{levels_enabled:true,xp_awards_enabled:true,achievements_enabled:true,enabledUserIds:['*'],weeklyLimit:3000}, 'spots/s':{status:'approved',lat:56.9496,lng:24.1052}, 'spots/other':{status:'approved',lat:56.9496,lng:24.1052}});}
async function sample(f, time, spot='s', gps=fix(time)) {return f.load('../lib/spot-visits.js').recordSpotVisit(f.db,'tester',spot,time,gps);}
test('five minutes of fresh fixes required before XP, country badge, visit or admin claim', async () => {
 const f=setup();
 f.rows.set('admin_rewards/r',{enabled:true,spotId:'s',startsAt:now,createdAt:now,endsAt:now+3600000,xp:200,title:{en:'Stay',ru:'Стой',lv:'Paliec'}});
 for(let t=0;t<300000;t+=30000) {
  const r=await sample(f,now+t);assert.equal(r.recorded,false);assert.equal(r.elapsedMs,t);
  assert.equal([...f.rows.keys()].some(k=>k.startsWith('spot_visit_records/')||k.startsWith('admin_reward_claims/')),false);
 }
 const result=await sample(f,now+300000);assert.equal(result.recorded,true);assert.equal(result.elapsedMs,300000);
 assert.equal((await sample(f,now+330000)).duplicate,true);
 const a=f.load('../lib/xp/achievements.js');
 assert.equal((await a.recordCountryAchievement('tester',fix(now+330000),{now:new Date(now+330000)})).awarded,true);
 const w=f.load('../lib/xp/weekly-tasks.js');await w.syncWeeklyTasks('tester',{now:new Date(now+330000)});
 const awards=[...f.rows.values()].filter(r=>r.action==='visit.weekly');assert.equal(awards.length,1);assert.equal(awards[0].amount,50);
 assert.equal([...f.rows.keys()].filter(k=>k.startsWith('admin_reward_claims/')).length,1);
});
test('outside radius and GPS gaps reset dwell; returning cannot resume old progress', async () => {
 const f=setup();await sample(f,now);assert.equal((await sample(f,now+30000)).elapsedMs,30000);
 assert.equal((await sample(f,now+40000,'s',fix(now+40000,57))).status,'outside_or_invalid');
 assert.equal((await sample(f,now+50000)).elapsedMs,0);
 assert.equal((await sample(f,now+120001)).elapsedMs,0);
});
test('replayed samples and simultaneous spots cannot multiply elapsed time', async () => {
 const f=setup();await sample(f,now);
 for(let t=1000;t<=50000;t+=1000) assert.equal((await sample(f,now+t,'s',fix(now))).elapsedMs,0);
 assert.equal((await sample(f,now+60000)).elapsedMs,10000);
 assert.equal((await sample(f,now+70000,'other')).elapsedMs,0);
 assert.equal((await sample(f,now+80000,'s')).elapsedMs,0);
});
test('500m never starts dwell', async () => {
 const f=setup();const gps=fix(now,56.9496 + 500/6371000*180/Math.PI);
 assert.equal((await sample(f,now,'s',gps)).recorded,false);
 assert.equal(f.rows.has('spot_visit_sessions/tester'),false);
});
test('three paid spots per day, seven per week, no backlog for forty same-day visits', async () => {
 const f=setup();
 for(let i=0;i<40;i++) f.rows.set('weekly_visit_records/r'+i,{userId:'tester',spotId:'s'+i,weekKey:'2026-09-21',dayKey:'2026-09-22',recordedAtMillis:now+i,event:false});
 await f.load('../lib/xp/weekly-tasks.js').syncWeeklyTasks('tester',{now:new Date(now)});
 const awards=[...f.rows.values()].filter(r=>r.action==='visit.weekly');
 assert.equal(awards.length,3);assert.equal(awards.reduce((n,r)=>n+r.amount,0),150);
});

test('already visited flag suppresses repeat UI without bypassing new task dwell', async () => {
 const f=setup();
 for(let t=0;t<=300000;t+=30000) await sample(f,now+t);
 await sample(f,now+400000,'s',fix(now+400000,57));
 const result=await sample(f,now+430000);
 assert.equal(result.alreadyVisited,true);
 assert.equal(result.recorded,false);
 assert.equal(result.elapsedMs,0);
});
