const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./support');
const start=Date.parse('2026-10-11T12:00:00Z');
const fix=t=>({latitude:0,longitude:0,accuracy:5,isMocked:false,recordedAtMillis:t});
function setup(){return fixture({'spots/s':{status:'approved',lat:0,lng:0}});}
async function sample(f,t,sharing=true){
 if(sharing) f.rows.set('live_locations/tester',{updatedAt:t,expiresAt:t+60000});
 return f.load('../lib/spot-visits.js').recordSpotVisit(f.db,'tester','s',t,fix(t));
}
test('fresh direct GPS cannot bypass stopped, expired, stale or mocked live sharing',async()=>{
 for(const live of [null,{updatedAt:start,expiresAt:start},{updatedAt:start-60001,expiresAt:start+60000},{updatedAt:start,expiresAt:start+60000,isMocked:true}]) {
  const f=setup();if(live)f.rows.set('live_locations/tester',live);
  const r=await sample(f,start,false);assert.equal(r.status,'sharing_required');assert.equal(r.recorded,false);
  assert.equal(f.rows.has('spot_visit_sessions/tester'),false);
 }
});
test('stopping sharing clears dwell; restarting sharing requires a fresh five minutes',async()=>{
 const f=setup();await sample(f,start);assert.equal((await sample(f,start+30000)).elapsedMs,30000);
 f.rows.delete('live_locations/tester');await sample(f,start+45000,false);
 assert.equal((await sample(f,start+50000)).elapsedMs,0);
 // Even without a sample during the stopped window, a recreated sharing document resets dwell.
 f.createTimes.set('live_locations/tester',start+55000);
 assert.equal((await sample(f,start+60000)).elapsedMs,0);
 for(let t=90000;t<=360000;t+=30000)await sample(f,start+t);
 assert.equal([...f.rows.values()].filter(r=>r.action==='visit.daily').length,1);
});
test('daily status is private and resets at Riga midnight including DST',async()=>{
 const f=setup();const {visitStatus,nextVisitDayAt,rigaDay}=f.load('../lib/spot-visits.js');
 f.rows.set('spot_visit_records/a',{userId:'tester',spotId:'s',status:'verified',dayKey:rigaDay(start)});
 f.rows.set('spot_visit_records/b',{userId:'other',spotId:'private',status:'verified',dayKey:rigaDay(start)});
 const status=await visitStatus(f.db,'tester',start);assert.deepEqual(Array.from(status.spotIds),['s']);
 assert.equal((await visitStatus(f.db,'tester',status.expiresAt)).spotIds.length,0);
 for(const stamp of ['2026-03-29T00:00:00Z','2026-10-25T00:00:00Z']){
  const t=Date.parse(stamp),end=nextVisitDayAt(t);
  assert.equal(rigaDay(end-1),rigaDay(t));assert.notEqual(rigaDay(end),rigaDay(t));
 }
});
