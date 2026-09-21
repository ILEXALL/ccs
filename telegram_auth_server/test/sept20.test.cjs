const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture,completedDwell}=require('./support');
const now=Date.now();
const gps={latitude:56.95,longitude:24.1,accuracy:8,isMocked:false,recordedAtMillis:now};
function setup(extra={}) {return fixture({
 'app_config/xp':{levels_enabled:true,xp_awards_enabled:true,achievements_enabled:true,enabledUserIds:['*'],weeklyLimit:3000},
 'users/tester':{username:'driver',publicProfile:true},
 'spots/e':{status:'approved',isTemporary:true,visibility:'public',startsAt:now-10000,expiresAt:now+3600000,lat:56.95,lng:24.1},...extra,
});}
async function call(f,body,uid='tester') {
 completedDwell(f,uid,body.spotId,body.gpsFix?.recordedAtMillis || now);
 const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;},setHeader(){}};
 await f.load('../handlers/spot-visit.js')({method:'POST',headers:{authorization:'Bearer '+uid},body},res);
 return res;
}
test('event attendance credits 200 once, cumulative bronze, reason and level-up notification',async()=>{
 const f=setup();let res=await call(f,{spotId:'e',gpsFix:gps,userId:'victim'});
 assert.equal(res.code,200);assert.equal(res.body.result.xp.amount,200);
 const total=f.rows.get('xp_user_stats/tester').xpTotal;
 assert.equal(total,250); // 200 attendance + 25 attendance bronze + 25 visit bronze
 res=await call(f,{spotId:'e',gpsFix:gps});assert.equal(res.code,200);
 assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,total);
 const bells=[...f.rows].filter(([k])=>k.startsWith('user_notifications/')).map(([,v])=>v);
 assert.ok(bells.some(v=>v.body.includes('200 XP — Event attended')&&v.levelUp>1));
 assert.ok(bells.some(v=>v.title==='Achievement unlocked'&&v.body.includes('Event attendance')));
 assert.equal(f.rows.has('xp_user_stats/victim'),false);
});
test('attendance respects event time, membership, moderation, GPS and unique per-event keys',async()=>{
 for(const patch of [{startsAt:now+999999},{expiresAt:now-1},{status:'pending'},{status:'rejected'},{deleted:true},{visibility:'group',sharedGroupIds:['g']}]) {
  const f=setup();Object.assign(f.rows.get('spots/e'),patch);
  assert.equal((await call(f,{spotId:'e',gpsFix:gps})).code,403);
  assert.equal(f.rows.has('xp_user_stats/tester'),false);
 }
 const f=setup({'chats/g':{isGroup:true,memberIds:['tester']}});
 Object.assign(f.rows.get('spots/e'),{visibility:'group',sharedGroupIds:['g']});
 assert.equal((await call(f,{spotId:'e',gpsFix:gps})).code,200);
 f.rows.set('spots/e2',{...f.rows.get('spots/e'),visibility:'public'});
 assert.equal((await call(f,{spotId:'e2',gpsFix:gps})).body.result.xp.amount,200);
});
test('mock and impossible travel flag all admins once; poor GPS never accuses users',async()=>{
 const f=setup({'users/a':{role:'admin'},'users/b':{role:'admin'},'users/m':{role:'moderator'}});
 // The test double deliberately has no FCM: assert durable admin bell recipients.
 for(const [k,v] of f.rows) if(k.startsWith('users/')) v.username=k;
 f.db.collectionOriginal=f.db.collection;
 f.db.collection=function(name){const query=this.collectionOriginal(name);const doc=query.doc;
  query.doc=(id)=>{const ref=doc(id);ref.set=async(data)=>f.rows.set(ref.key,data);return ref;};return query;};
 const {assessLocation}=f.load('../lib/location-integrity.js');
 assert.equal(await assessLocation('tester',{...gps,accuracy:500},now),false);
 assert.equal([...f.rows.keys()].filter(k=>k.startsWith('admin_notifications/')).length,0);
 assert.equal(await assessLocation('tester',gps,now),true);
 assert.equal(await assessLocation('tester',{...gps,latitude:1,recordedAtMillis:now+1000},now+1000),false);
 assert.equal(await assessLocation('tester',{...gps,isMocked:true},now+2000),false);
 const alerts=[...f.rows].filter(([k])=>k.startsWith('admin_notifications/')).map(([,v])=>v);
 assert.deepEqual(alerts.map(v=>v.userId).sort(),['a','b']);
 assert.ok(alerts.every(v=>v.body.includes('users/tester')));
});
test('attendance catalog has the requested five thresholds and rewards',()=>{
 const f=setup();const rows=f.load('../lib/xp/achievements.js').catalog().filter(v=>v.category==='attendance');
 assert.deepEqual(Array.from(rows,v=>[v.threshold,v.xp]),[[1,25],[5,100],[25,200],[50,350],[100,600]]);
});
test('search finds a low-ranked username or display name beyond the first hundred',async()=>{
 const f=setup();for(let i=0;i<250;i++){
  f.rows.set('users/u'+i,{username:'driver'+i,name:i===249?'Distinct Name':'Driver',publicProfile:true});
  f.rows.set('xp_user_stats/u'+i,{xpTotal:1000-i,userId:'u'+i,level:3});
 }
 for(const [key,user] of f.rows) if(key.startsWith('users/')) user.country='LV';
 const handler=f.load('../handlers/xp-leaderboard.js');
 const res={status(c){this.code=c;return this;},json(v){this.body=v;return this;},setHeader(){}};
 await handler({method:'POST',headers:{authorization:'Bearer tester'},body:{search:'distinct',limit:10}},res);
 assert.equal(res.code,200);assert.equal(res.body.result.entries.length,1);assert.equal(res.body.result.entries[0].userId,'u249');
});
