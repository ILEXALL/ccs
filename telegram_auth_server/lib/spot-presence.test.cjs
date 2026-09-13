const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

function fixture(file) {
  let now=1000000;
  const records=new Map([
    ['users/driver',{username:'driver'}],
    ['spots/permanent',{name:'Parking',status:'approved',lat:0,lng:0}],
    ['spots/temporary',{name:'Meet',status:'approved',lat:0,lng:0,isTemporary:true,expiresAt:99999999}],
    ['friendships/a',{userIds:['driver','alice']}],
    ['friendships/b',{userIds:['bob','driver']}],
    ['friendships/unrelated',{userIds:['eve','mallory']}],
  ]);
  const deliveries=[];
  function snap(p){return {id:p.split('/').at(-1),exists:records.has(p),data:()=>structuredClone(records.get(p))};}
  function ref(p){return {path:p,get:async()=>snap(p)};}
  const db={collection:name=>({doc:id=>ref(name+'/'+id),where:(key,op,value)=>{
    const query={get:async()=>({docs:[...records.keys()].filter(p=>p.startsWith(name+'/')&&(op==='array-contains'?records.get(p)[key]?.includes(value):records.get(p)[key]===value)).map(snap)}),select:()=>query};return query;
  }}),runTransaction:async fn=>fn({get:r=>r.get(),set:(r,v)=>records.set(r.path,v)})};
  let source=fs.readFileSync(file,'utf8');
  source=source.slice(source.indexOf('const SPOT_PRESENCE_RADIUS_METERS'),source.indexOf('async function handleFriendLiveSharing'));
  const context={db,Date:{now:()=>now},admin:{firestore:{FieldValue:{serverTimestamp:()=>now}}},
    timestampToMillis:v=>typeof v==='number'?v:0,cleanText:(v,f='')=>typeof v==='string'&&v.trim()?v.trim():f,
    cleanStringArray:v=>Array.isArray(v)?v.filter(x=>typeof x==='string'):[],userHasActiveBan:u=>u.banned===true,
    sendPushToUser:async args=>{deliveries.push(args);return 1;},exports:{}};
  vm.runInNewContext(source+'\nexports.advance=advanceSpotPresence; exports.handle=handleFriendAtSpot;',context);
  const live=(lat=0)=>({lat,lng:0,updatedAt:now,expiresAt:99999999});
  return {records,deliveries,live,advance:context.exports.advance,
    step:async(lat=0)=>{records.set('live_locations/driver',live(lat));return context.exports.handle('driver',{recipientUserIds:['eve'],spotId:'forged',lat:80});},
    now:()=>now,tick:(ms=60000)=>{now+=ms;},handle:context.exports.handle};
}
for(const relative of ['../api/push-notification.js','../../api/push-notification.js']) {
  const file=path.resolve(__dirname,relative);
  test(`${relative}: five fresh minutes within 200m notify all actual friends for both spot types once`,async()=>{
    const f=fixture(file);
    // ~150m north: inside requested 200m but outside old 100m radius.
    await f.step(0.00135);
    for(let i=0;i<4;i++){f.tick();await f.step(0.00135);}
    assert.equal(f.deliveries.length,0);
    f.tick();await f.step(0.00135);
    assert.equal(f.deliveries.length,4);
    assert.deepEqual([...new Set(f.deliveries.map(d=>d.userId))].sort(),['alice','bob']);
    assert(f.deliveries.every(d=>d.data.type==='friend_at_spot'&&d.settingName==='friendAtSpotNotifications'));
    f.tick();await f.step(0.00135);
    assert.equal(f.deliveries.length,4);
  });
  test(`${relative}: leaving radius resets dwell and returning creates a new visit`,async()=>{
    const f=fixture(file);await f.step();
    for(let i=0;i<5;i++){f.tick();await f.step();}
    assert.equal(f.deliveries.length,4);
    const previousKey=f.deliveries[0].deliveryKey;
    f.tick();await f.step(0.003);
    f.tick();await f.step();
    for(let i=0;i<4;i++){f.tick();await f.step();}
    assert.equal(f.deliveries.length,4);
    f.tick();await f.step();
    assert.equal(f.deliveries.length,8);
    assert.notEqual(f.deliveries[4].deliveryKey,previousKey);
  });
  test(`${relative}: missing samples and stopped sharing never count as five minutes`,async()=>{
    const f=fixture(file);await f.step();
    f.tick(6*60000);await f.step();
    assert.equal(f.deliveries.length,0);
    f.records.delete('live_locations/driver');
    await f.handle('driver',{});
    assert.deepEqual(Object.keys(f.records.get('spot_presence/driver').visits),[]);
    f.tick();await f.step();
    assert.equal(f.deliveries.length,0);
  });
  test(`${relative}: repeated stale samples, expired temporary spots, and inactive sharing are ignored`,()=>{
    const f=fixture(file);const spots=[{id:'p',...f.records.get('spots/permanent')}];
    const live=f.live();let state=f.advance({},live,spots,f.now()).state;
    f.tick(5*60000);
    assert.equal(f.advance(state,live,spots,f.now()).ready.length,0);
    const expired={...f.live(),expiresAt:f.now()-1};
    assert.equal(f.advance(state,expired,spots,f.now()).ready.length,0);
    const result=f.advance({},f.live(),[{id:'t',status:'approved',lat:0,lng:0,isTemporary:true,expiresAt:f.now()-1}],f.now());
    assert.equal(Object.keys(result.state.visits).length,0);
  });
}
