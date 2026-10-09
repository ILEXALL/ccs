const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./support');
const start=Date.parse('2026-10-10T12:00:00Z');
function setup(){return fixture({'spots/s':{status:'approved',lat:0,lng:0}});}
const fix=t=>({latitude:0,longitude:0,accuracy:5,isMocked:false,recordedAtMillis:t});
async function stay(f,t){let r;for(let i=0;i<=300000;i+=30000)r=await f.load('../lib/spot-visits.js').recordSpotVisit(f.db,'tester','s',t+i,fix(t+i));return r;}
test('daily visit requires five minutes and awards once per server calendar day',async()=>{
 const f=setup();await stay(f,start);await stay(f,start+600000);
 let rows=[...f.rows.values()].filter(r=>r.action==='visit.daily');assert.equal(rows.length,1);assert.equal(rows[0].amount,50);
 const next=start+86400000;
 const first=await f.load('../lib/spot-visits.js').recordSpotVisit(f.db,'tester','s',next,fix(next));
 assert.equal(first.alreadyVisited,false);assert.equal(first.elapsedMs,0);
 await stay(f,next);rows=[...f.rows.values()].filter(r=>r.action==='visit.daily');assert.equal(rows.length,2);
});
test('event pays 400 once and not again on another day',async()=>{
 const f=setup();Object.assign(f.rows.get('spots/s'),{isTemporary:true,startsAt:start-1000,expiresAt:start+3*86400000});
 await stay(f,start);await stay(f,start+86400000);
 const rows=[...f.rows.values()].filter(r=>r.action==='event.attended');assert.equal(rows.length,1);assert.equal(rows[0].amount,400);
});
test('moving sharing earns nothing on activation or when stationary, then 100 at one hour',async()=>{
 const f=setup(),m=f.load('../lib/xp/moving-share.js');
 const send=async(t,lng,extra={})=>{f.rows.set('live_locations/tester',{lat:0,lng,accuracy:5,isMocked:false,updatedAt:t,recordedAtMillis:t,expiresAt:start+5*3600000,...extra});return m.recordMovingShare('tester',t);};
 for(let i=0;i<=120;i++)await send(start+i*30000,0);
 assert.equal([...f.rows.values()].filter(r=>r.action==='sharing.hour').length,0);
 for(let i=1;i<120;i++)await send(start+3600000+i*30000,i*.001);
 assert.equal([...f.rows.values()].filter(r=>r.action==='sharing.hour').length,0);
 await send(start+7200000,.12);await m.recordMovingShare('tester',start+7200000);
 const rows=[...f.rows.values()].filter(r=>r.action==='sharing.hour');assert.equal(rows.length,1);assert.equal(rows[0].amount,100);
});
test('replayed fixes, gaps, mock locations and jitter do not add moving time',()=>{
 const f=setup(),{advanceMovingShare:advance}=f.load('../lib/xp/moving-share.js');
 const live=(t,lng=0)=>({lat:0,lng,accuracy:10,isMocked:false,updatedAt:t,recordedAtMillis:t,expiresAt:start+3600000});
 const initial=advance({},live(start),start);
 assert.equal(advance(initial,live(start+30000,.00001),start+30000).movingMs,0);
 assert.equal(advance(initial,live(start,1),start+30000).movingMs,0);
 assert.equal(advance(initial,live(start+120000,.1),start+120000).movingMs,0);
 assert.equal(advance(initial,{...live(start+30000,.001),isMocked:true},start+30000).movingMs,0);
});
