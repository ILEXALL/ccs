const test=require('node:test');const assert=require('node:assert/strict');const {fixture}=require('./support');
const now=Date.parse('2026-09-19T12:00:00Z');
function setup(){return fixture({'app_config/xp':{levels_enabled:true,xp_awards_enabled:true,achievements_enabled:true,enabledUserIds:['*'],weeklyLimit:3000,timezone:'Europe/Riga'},'users/tester':{role:'user',verified:true},'spots/s':{status:'approved',lat:0,lng:0}});}
const gps={latitude:0,longitude:0,accuracy:10,isMocked:false,recordedAtMillis:now};
test('GPS button records without live sharing, once across days and account sessions',async()=>{
 const f=setup();const {recordSpotVisit}=f.load('../lib/spot-visits.js');const achievements=f.load('../lib/xp/achievements.js');
 assert.equal((await recordSpotVisit(f.db,'tester','s',now,gps)).duplicate,false);
 const later=now+86400000;
 assert.equal((await recordSpotVisit(f.db,'tester','s',later,{...gps,recordedAtMillis:later})).duplicate,true);
 await achievements.syncAchievements('tester',{now:new Date(later)});
 const firstXp=f.rows.get('xp_user_stats/tester').xpTotal;
 const board=await achievements.syncAchievements('tester',{now:new Date(later)});
 assert.equal(board.items.find(i=>i.id==='visits.1').progress,1);
 assert.equal(board.items.find(i=>i.id==='visits.1').status,'confirmed');
 assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,firstXp);
 assert.equal([...f.rows.keys()].filter(k=>k.startsWith('spot_visit_records/')).length,1);
});
test('GPS visit rejects bad fixes and cannot use a forged user id',async()=>{
 const f=setup();const {recordSpotVisit}=f.load('../lib/spot-visits.js');
 for(const change of [{isMocked:true},{isMocked:undefined},{accuracy:101},{accuracy:undefined},{recordedAtMillis:now-150001},{recordedAtMillis:now+5000},{latitude:1}]){
  await assert.rejects(recordSpotVisit(f.db,'tester','s',now,{...gps,...change}));
 }
 assert.equal([...f.rows.keys()].filter(k=>k.startsWith('spot_visit_records/')).length,0);
});
test('Moderator rows follow target role on own and public boards, including demotion',async()=>{
 const f=setup();const a=f.load('../lib/xp/achievements.js');f.rows.set('users/viewer',{role:'moderator'});
 for(const role of ['user','admin','moderator','user']){
  f.rows.get('users/tester').role=role;
  const own=await a.syncAchievements('tester',{now:new Date(now)});const pub=await a.publicAchievements('viewer','tester');
  for(const board of [own,pub])assert.equal(board.items.filter(i=>i.category==='moderator').length,role==='moderator'?5:0);
 }
});
test('approved events unlock cumulative Event tiers; pending, rejected and deleted do not count',async()=>{
 const f=setup();const a=f.load('../lib/xp/achievements.js');
 for(let i=0;i<5;i++)f.rows.set('spots/e'+i,{addedByUid:'tester',ownerUid:'tester',isTemporary:true,status:'approved'});
 f.rows.set('spots/pending',{addedByUid:'tester',isTemporary:true,status:'pending'});
 f.rows.set('spots/rejected',{addedByUid:'tester',isTemporary:true,status:'rejected'});
 f.rows.set('spots/deleted',{addedByUid:'tester',isTemporary:true,status:'approved',deleted:true});
 const board=await a.syncAchievements('tester',{now:new Date(now)});
 assert.equal(board.items.find(i=>i.id==='meets.5').progress,5);
 assert.equal(board.items.find(i=>i.id==='meets.5').status,'confirmed');
 assert.equal(board.items.find(i=>i.id==='meets.5').title.en,'Events');
 assert.equal(board.items.find(i=>i.id==='spots.1').progress,0);
 const xp=f.rows.get('xp_user_stats/tester').xpTotal;
 await a.syncAchievements('tester',{now:new Date(now)});assert.equal(f.rows.get('xp_user_stats/tester').xpTotal,xp);
});
test('group notifications target added members only and approval key survives later group updates',async()=>{
 const f=setup();f.rows.set('chats/g',{isGroup:true,name:'Drivers',memberIds:['owner','tester'],updatedAt:123});
 f.rows.set('chats/g/join_requests/tester',{status:'accepted',decidedAt:120});
 const {notifyGroupMembers}=f.load('../lib/group-notifications.js');const sent=[];const send=async msg=>sent.push(msg);
 await notifyGroupMembers('g','owner',['owner','tester','tester','outsider'],false,send);
 assert.equal(sent.length,1);assert.equal(sent[0].userId,'tester');assert.equal(sent[0].data.chatId,'g');
 await notifyGroupMembers('g','owner',['tester'],true,send);const key=sent[1].deliveryKey;
 f.rows.get('chats/g').updatedAt=456;await notifyGroupMembers('g','owner',['tester'],true,send);
 assert.equal(sent[2].deliveryKey,key);assert.equal(sent[2].data.status,'accepted');
 f.rows.get('chats/g/join_requests/tester').status='rejected';await notifyGroupMembers('g','owner',['tester'],true,send);assert.equal(sent.length,3);
});
