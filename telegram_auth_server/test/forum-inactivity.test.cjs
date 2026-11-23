const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./support');
const {inactivityWarning,dispatchForumInactivity}=require('../lib/forum-inactivity');
const DAY=86400000,now=Date.now(),activity=now-29*DAY;
const topic={authorId:'author',title:'Meetup',createdAt:activity,status:'approved'};
test('warning is due exactly 24h before hiding and new replies reset the deadline',()=>{
 assert.equal(inactivityWarning(topic,now-1),null);
 assert.equal(inactivityWarning(topic,now).hidesAt,now+DAY);
 for(const patch of [{lastReplyAt:now},{deleted:true},{status:'pending'},{authorId:''},{autoExpiresAt:now+1000},{createdAt:now-30*DAY}])
  assert.equal(inactivityWarning({...topic,...patch},now),null);
 assert.equal(inactivityWarning({...topic,createdAt:{toMillis:()=>activity}},now).activity,activity);
});
test('worker targets authors, resumes pages and uses one delivery identity per inactivity period',async()=>{
 const f=fixture();for(let i=0;i<230;i++)f.rows.set('forum_topics/t'+String(i).padStart(3,'0'),topic);
 const sent=new Map(),send=async m=>sent.set(m.deliveryKey,m);
 const args={db:f.db,send,now};
 assert.equal((await dispatchForumInactivity(args)).scanned,200);
 await dispatchForumInactivity(args);assert.equal(sent.size,230);
 await dispatchForumInactivity(args);assert.equal(sent.size,230);
 const m=[...sent.values()][0];assert.equal(m.userId,'author');
 assert.match(m.body,/24 hours/);assert.equal(m.data.type,'forum_inactivity_warning');
 assert.ok(m.notificationId);assert.ok(m.data.topicId);
 f.rows.set('forum_topics/t000',{...topic,lastReplyAt:now});
 await dispatchForumInactivity({...args,now:now+29*DAY});
 await dispatchForumInactivity({...args,now:now+29*DAY});
 assert.equal(sent.size,231);
});
test('failed sends retry and an active lease skips overlapping workers',async()=>{
 const f=fixture({'forum_topics/a':topic});let fail=true;const keys=[];
 const args={db:f.db,now,send:async m=>{keys.push(m.deliveryKey);if(fail){fail=false;throw Error('retry');}}};
 await assert.rejects(dispatchForumInactivity(args),/retry/);
 await dispatchForumInactivity(args);assert.equal(keys[0],keys[1]);
 f.rows.set('forum_inactivity_jobs/scheduler',{leaseUntil:now+1000});
 assert.equal((await dispatchForumInactivity(args)).busy,true);
});
