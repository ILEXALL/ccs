const {test}=require('node:test');
const assert=require('node:assert/strict');
const {prepareNearbyAdminRewards}=require('../lib/xp/nearby-admin-rewards');
const {coordinates,distanceMeters}=require('../lib/spot-visits');
function fixture(){
 const docs=new Map([['admin_rewards/task',{enabled:true,spotId:'target',startsAt:0,createdAt:0,endsAt:99999999,xp:100,title:{en:'Task'}}],['spots/target',{status:'approved',lat:57,lng:24}]]);
 const db={collection:c=>({doc:id=>({path:c+'/'+id})})};
 const tx={get:async ref=>({exists:docs.has(ref.path),data:()=>docs.get(ref.path)}),create:(ref,data)=>{assert.ok(!docs.has(ref.path));docs.set(ref.path,data);}};
 return {docs,db,tx};
}
test('overlapping tasks accrue independently of the selected spot, for each user, and retry safely',async()=>{
 const f=fixture(); const sessions={};
 for(let now=1000;now<=301000;now+=15000) for(const userId of ['one','two']){
   const result=await prepareNearbyAdminRewards(f.db,f.tx,{userId,user:{},position:{lat:57,lng:24.0001},sample:now,now,session:sessions[userId]||{},candidates:[{id:'task'}],coordinates,distanceMeters});
   result.write();sessions[userId]={spotId:'different-nearby-spot',rewardDwell:result.progress};
 }
 assert.equal([...f.docs.keys()].filter(k=>k.startsWith('admin_reward_claims/')).length,2);
 const retry=await prepareNearbyAdminRewards(f.db,f.tx,{userId:'one',user:{},position:{lat:57,lng:24},sample:316000,now:316000,session:sessions.one,candidates:[{id:'task'}],coordinates,distanceMeters});
 assert.equal(retry.claimed,true);retry.write();
 assert.equal([...f.docs.keys()].filter(k=>k.startsWith('admin_reward_claims/')).length,2);
});
test('departure, missing samples, and inaccessible targets cannot earn a task',async()=>{
 const f=fixture();const base={userId:'one',user:{},position:{lat:57,lng:24},candidates:[{id:'task'}],coordinates,distanceMeters};
 const old={rewardDwell:{task:{elapsedMs:299000,lastSeenAt:1000,lastSampleAt:1000}}};
 let r=await prepareNearbyAdminRewards(f.db,f.tx,{...base,session:old,now:70000,sample:70000});assert.equal(r.claimed,false);assert.equal(r.progress.task.elapsedMs,0);
 r=await prepareNearbyAdminRewards(f.db,f.tx,{...base,position:{lat:58,lng:24},session:old,now:2000,sample:2000});assert.deepEqual(r.progress,{});
 f.docs.get('spots/target').visibility='group';
 r=await prepareNearbyAdminRewards(f.db,f.tx,{...base,session:old,now:2000,sample:2000});assert.equal(r.claimed,false);
});
