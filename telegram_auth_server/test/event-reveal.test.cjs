const test=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./support');
const {dispatchEventReveals,revealIsDue,recipientMatches}=require('../lib/event-reveal');
const now=Date.now(), since=now-60000;
const spot={isTemporary:true,status:'approved',visibility:'public',countryCode:'LV',showOnMapAt:now-1000,startsAt:now+3600000,expiresAt:now+7200000,name:'Meet'};
const countryKey=s=>({Latvia:'LV',Latvija:'LV',Estonia:'EE'}[s] || s);
test('only approved public scheduled reveals qualify, with no pre-activation backlog',()=>{
 assert.equal(revealIsDue(spot,now,since),true);
 for(const change of [{visibility:'group'},{visibility:'unknown'},{status:'pending'},{deleted:true},{showOnMapAt:now+1},{showOnMapAt:since-1},{showOnMapAt:null},{expiresAt:now},{isTemporary:false}])assert.equal(revealIsDue({...spot,...change},now,since),false);
 assert.equal(recipientMatches({country:'Latvia'},spot,countryKey),true);
 assert.equal(recipientMatches({country:'EE',spotCountryFilters:['LV']},spot,countryKey),false);
 assert.equal(recipientMatches({},spot,countryKey),false);
 assert.equal(recipientMatches({country:'LV'},{...spot,verifiedOnly:true},countryKey),false);
});
test('reveal dispatch paginates beyond 500, targets profile country and records event deep links once',async()=>{
 const f=fixture({'spots/public':{...spot},'spots/private':{...spot,visibility:'group'}});
 for(let i=0;i<630;i++)f.rows.set('users/u'+String(i).padStart(4,'0'),{country:i<615?'LV':'EE'});
 const sent=[];const args={db:f.db,send:async msg=>sent.push(msg),countryKey,since,now};
 await dispatchEventReveals(args);assert.equal(sent.length,615);
 assert.ok(sent.every(m=>m.data.spotId==='public'&&m.data.type==='event_location_revealed'&&m.settingName==='newSpotNotifications'));
 await dispatchEventReveals(args);assert.equal(sent.length,615);
});
test('failed pages retry with stable per-user delivery keys and preserve completed recipients',async()=>{
 const f=fixture({'spots/public':{...spot}});for(let i=0;i<70;i++)f.rows.set('users/u'+i,{country:'LV'});
 const deliveries=new Set();let fail=true;
 const send=async m=>{if(fail&&m.userId==='u40'){fail=false;throw Error('temporary');}deliveries.add(m.deliveryKey+':'+m.userId);};
 const args={db:f.db,send,countryKey,since,now};
 await assert.rejects(dispatchEventReveals(args),/temporary/);
 await dispatchEventReveals(args);assert.equal(deliveries.size,70);
});
test('concurrent scheduler run is skipped and a private edit stops the next recipient page',async()=>{
 const f=fixture({'spots/public':{...spot},'event_reveal_jobs/scheduler':{leaseUntil:now+10000}});
 assert.equal((await dispatchEventReveals({db:f.db,send:()=>assert.fail(),countryKey,since,now})).busy,true);
 f.rows.delete('event_reveal_jobs/scheduler');for(let i=0;i<80;i++)f.rows.set('users/u'+i,{country:'LV'});
 let count=0;await dispatchEventReveals({db:f.db,countryKey,since,now,send:async()=>{if(++count===1)f.rows.get('spots/public').visibility='group';}});
 assert.ok(count<=25);
});

test('scheduler endpoint fails closed for missing and incorrect secrets',async()=>{
 const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
 for(const [secret,auth] of [[undefined,'Bearer x'],['secret',''],['secret','Bearer wrong'],['secret','Bearer secrex']]) {
  const module={exports:{}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../handlers/event-reveals.js'),'utf8'),{
   module,Buffer,process:{env:{EVENT_REVEAL_WORKER_SECRET:secret}},
   require:id=>id==='node:crypto'?require(id):{},
  });
  const res={status(n){this.code=n;return this;},json(v){this.value=v;return this;}};
  await module.exports({method:'GET',headers:{authorization:auth}},res);assert.equal(res.code,401);
 }
});

const {dispatchEventNotifications,reminderIsDue}=require('../lib/event-reveal');
test('five-hour reminder starts at boundary and excludes ended, private and unapproved events',()=>{
 const start=now+5*3600000;
 const event={...spot,startsAt:start,expiresAt:start+3600000};
 assert.equal(reminderIsDue(event,now-1,since),false);
 assert.equal(reminderIsDue(event,now,since),true);
 assert.equal(reminderIsDue(event,start,since),false);
 for(const patch of [{visibility:'group'},{visibility:'unknown'},{status:'pending'},{deleted:true},{isTemporary:false},{expiresAt:now}])
  assert.equal(reminderIsDue({...event,...patch},now,since),false);
 assert.equal(reminderIsDue(event,now,now+1),false);
});
test('both scheduled notifications reach every same-country recipient beyond 500, once each',async()=>{
 const event={...spot,startsAt:now+5*3600000,expiresAt:now+6*3600000};
 const f=fixture({'spots/public':event,'spots/private':{...event,visibility:'group'}});
 for(let i=0;i<640;i++)f.rows.set('users/u'+String(i).padStart(4,'0'),{country:i<620?'Latvia':'EE'});
 const sent=[];
 const args={db:f.db,send:async m=>sent.push(m),countryKey,since,now};
 await dispatchEventNotifications(args);
 assert.equal(sent.length,1240);
 for(const type of ['temporary_spot_today','event_location_revealed']) {
  assert.equal(sent.filter(m=>m.data.type===type).length,620);
 }
 assert.ok(sent.every(m=>m.communityCountry==='LV'&&m.data.spotId==='public'));
 await dispatchEventNotifications(args);
 assert.equal(sent.length,1240);
 // Legacy app-triggered requests reuse the scheduler job and do not duplicate it.
 await dispatchEventNotifications({...args,kinds:['reminder'],spotId:'public'});
 assert.equal(sent.length,1240);
});
test('reminder retry resumes failed pages with stable keys and no audience truncation',async()=>{
 const f=fixture({'spots/public':{...spot,startsAt:now+5*3600000,expiresAt:now+6*3600000}});
 for(let i=0;i<650;i++)f.rows.set('users/u'+String(i).padStart(4,'0'),{country:'LV'});
 const delivered=new Set();let fail=true;
 const args={db:f.db,countryKey,since,now,kinds:['reminder'],send:async m=>{
  if(m.userId==='u0520'&&fail){fail=false;throw Error('retry');}
  delivered.add(m.deliveryKey+':'+m.userId);
 }};
 await assert.rejects(dispatchEventNotifications(args),/retry/);
 await dispatchEventNotifications(args);
 assert.equal(delivered.size,650);
});
test('rescheduled reminders use a new start-specific key and no reveal duplicates',async()=>{
 const event={...spot,startsAt:now+5*3600000,expiresAt:now+6*3600000};
 const f=fixture({'spots/public':event,'users/recipient':{country:'LV'}});
 const sent=[];const args={db:f.db,countryKey,since:1,now,send:async m=>sent.push(m)};
 await dispatchEventNotifications(args);
 f.rows.set('spots/public',{...event,startsAt:now+4*3600000});
 await dispatchEventNotifications(args);
 assert.equal(sent.filter(m=>m.data.type==='temporary_spot_today').length,2);
 assert.equal(sent.filter(m=>m.data.type==='event_location_revealed').length,1);
});
