const test=require('node:test'),assert=require('node:assert/strict');
const {validTrace,makeRequest,parseMatch,limitKmh,createHandler,createAuthenticate,createReserve}=require('../lib/road-speed-limit');
const now=1800000000000;
const trace=()=>[0,1,2].map(i=>({lat:57+i*.0001,lng:24,at:now-2000+i*1000,speed:11,accuracy:4,speedAccuracy:1,heading:0,headingAccuracy:5,mocked:false}));
const match=()=>({route:[{properties:{id:'northbound',elementType:'Road',confidence:.99,speedLimits:{value:50,unit:'kmph',type:'Maximum'}}}],projectedPoints:trace().map(p=>({geometry:{coordinates:[p.lng,p.lat]},properties:{routeIndex:0,snapResult:'Matched'}}))});
test('POST contract uses lon/lat, matched headings/times, passenger car and metric',()=>{
 const r=makeRequest(trace(),'test-key'),url=r.url,body=JSON.parse(r.body);
 assert.equal(url.origin+url.pathname,'https://api.tomtom.com/snapToRoads/1');assert.equal(url.searchParams.get('vehicleType'),'PassengerCar');
 assert.equal(url.searchParams.get('measurementSystem'),'metric');assert.match(url.searchParams.get('fields'),/confidence/);
 assert.deepEqual(body.points[0].geometry.coordinates,[24,57]);assert.equal(body.points[0].properties.timestamp,new Date(now-2000).toISOString());
 assert.equal(body.points[0].properties.heading,0);assert.equal(body.points[0].properties.speed,undefined);
});
test('input rejects stale, unordered, mock, low accuracy, stationary and impossible jumps',()=>{
 assert.equal(validTrace(trace(),now),true);
 for(const patch of [{accuracy:30},{speedAccuracy:3},{mocked:true},{speed:1},{lat:NaN},{at:now-6000}]){const p=trace();Object.assign(p[2],patch);assert.equal(validTrace(p,now),false,JSON.stringify(patch));}
 const p=trace();p[2].lat=58;assert.equal(validTrace(p,now),false);assert.equal(validTrace(Array(13).fill(trace()[0]),now),false);
});
test('uses current matched road; unit conversion and unsupported types fail closed',()=>{
 assert.equal(parseMatch(match(),trace(),now).kilometersPerHour,50);
 assert.equal(limitKmh({value:30,unit:'mph',type:'Maximum'}),48.28032);
 for(const v of [null,{value:0,unit:'kmph',type:'Maximum'},{value:50,unit:'kmph',type:'Recommended'},{value:50,unit:'mps',type:'Maximum'},{value:50,unit:'kmph',type:'Maximum',conditions:['wet']}])assert.equal(limitKmh(v),null);
 const m=match();m.route.push({properties:{id:'next',elementType:'Road',confidence:1,speedLimits:{value:80,unit:'kmph',type:'Maximum'}}});m.projectedPoints[2].properties.routeIndex=1;assert.equal(parseMatch(m,trace(),now).roadId,'next');
});
test('poor/parallel-road snaps, reverse direction, missing and stale limits unavailable',()=>{
 for(const mutate of [m=>m.route[0].properties.confidence=.8,m=>m.projectedPoints[2].properties.snapResult='Unmatched',m=>m.projectedPoints[2].geometry.coordinates[0]+=.001,m=>m.projectedPoints.reverse(),m=>delete m.route[0].properties.speedLimits,m=>m.projectedPoints[2].properties.routeIndex=5]){const m=match();mutate(m);assert.equal(parseMatch(m,trace(),now).status,'unavailable');}
 assert.equal(parseMatch(match(),trace(),now+12000).status,'unavailable');
});
function fixture(overrides={}){let calls=0,reserves=0;const handler=createHandler({report:()=>{},authenticate:async()=> 'user',reserve:async()=>{reserves++;return true;},key:()=> 'test-key',now:()=>now,fetchImpl:async()=>{calls++;return {ok:true,text:async()=>JSON.stringify(match())};},...overrides});return{handler,get calls(){return calls;},get reserves(){return reserves;}};}
async function invoke(handler,req={}){const res={code:0,headers:{},setHeader(k,v){this.headers[k]=v;},status(n){this.code=n;return this;},json(v){this.value=v;return this;}};await handler({method:'POST',headers:{},body:{points:trace()},...req},res);return res;}
test('auth, unavailable configuration, throttle, errors and duplicate cache',async()=>{
 const f=fixture();assert.equal((await invoke(f.handler)).value.status,'available');await invoke(f.handler);assert.equal(f.calls,1);assert.equal(f.reserves,1);
 assert.equal((await invoke(f.handler,{method:'GET'})).code,405);
 const unauth=fixture({authenticate:async()=>null});assert.equal((await invoke(unauth.handler)).code,401);assert.equal(unauth.calls,0);
 const noKey=fixture({key:()=>''});assert.equal((await invoke(noKey.handler)).value.reason,'not_configured');assert.equal(noKey.reserves,0);
 const rate=fixture({reserve:async()=>false});assert.equal((await invoke(rate.handler)).code,429);assert.equal(rate.calls,0);
 const failure=fixture({fetchImpl:async()=>{throw Error('private upstream details');}});const r=await invoke(failure.handler);assert.equal(r.value.reason,'unavailable');assert.ok(!JSON.stringify(r).includes('private upstream'));
 const denied=fixture({fetchImpl:async()=>({ok:false,status:403})});assert.equal((await invoke(denied.handler)).value.reason,'provider_unavailable');
});
function database(initial={}){const data=new Map(Object.entries(initial));const ref=path=>({path,get:async()=>({data:()=>data.get(path)})});return{data,collection:c=>({doc:id=>ref(c+'/'+id)}),runTransaction:async fn=>fn({get:r=>r.get(),set:(r,v)=>data.set(r.path,v)})};}
test('Firebase token is verified with revocation check and inactive users are denied',async()=>{
 const db=database({'users/u':{}});let revoked;const admin={auth:()=>({verifyIdToken:async(t,r)=>{assert.equal(t,'token');revoked=r;return{uid:'u'};}})};
 const auth=createAuthenticate(admin,db);assert.equal(await auth({headers:{}}),null);assert.equal(await auth({headers:{authorization:'Bearer token'}}),'u');assert.equal(revoked,true);
 db.data.set('users/u',{banned:true});assert.equal(await auth({headers:{authorization:'Bearer token'}}),null);
});
test('durable per-user/global/day/month limits contain no travel trace',async()=>{
 const db=database(),reserve=createReserve(db,{TOMTOM_SPEED_LIMIT_DAILY_BUDGET:'2'});
 assert.equal(await reserve('u',now),true);assert.equal(await reserve('u',now+1000),false);assert.equal(await reserve('v',now+100),false);
 assert.equal(await reserve('u',now+5000),true);assert.equal(await reserve('v',now+10000),false);
 for(const v of db.data.values())assert.ok(Object.keys(v).every(k=>['count','lastAt'].includes(k)));
 const db2=database(),month=createReserve(db2,{TOMTOM_SPEED_LIMIT_MONTHLY_BUDGET:'1'});assert.equal(await month('u',now),true);assert.equal(await month('u',now+86400000),false);
});

test('uncertain heading uses the matched trace direction without sending a noisy heading',()=>{
 const points=trace().map(p=>({...p,heading:180,headingAccuracy:50}));
 assert.equal(validTrace(points,now),true);
 assert.equal(JSON.parse(makeRequest(points,'test').body).points[0].properties.heading,undefined);
 const r=parseMatch(match(),points,now);assert.equal(r.status,'available');assert.equal(r.heading,0);
});

test('missing device course and moderate GPS accuracy still use strict matched-road evidence',()=>{
 const points=trace().map(p=>({...p,accuracy:20,heading:-1,headingAccuracy:-1}));
 assert.equal(validTrace(points,now),true);
 assert.equal(JSON.parse(makeRequest(points,'test').body).points[0].properties.heading,undefined);
 assert.equal(parseMatch(match(),points,now).kilometersPerHour,50);
 const poor=match();poor.route[0].properties.confidence=.8;
 assert.equal(parseMatch(poor,points,now).status,'unavailable');
});

test('diagnostics report provider status without coordinates, keys or user identity',async()=>{
 const logs=[];
 const f=fixture({report:r=>logs.push(r),fetchImpl:async()=>({ok:false,status:403})});
 await invoke(f.handler);
 assert.deepEqual(logs,[{status:'unavailable',reason:'provider_unavailable',httpStatus:200,providerStatus:403,durationMs:0}]);
});
