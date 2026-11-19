// Legacy TomTom Snap to Roads. No country defaults or average-speed substitution.
const crypto=require('node:crypto');
const unknown=(reason,retryAfterSeconds=15)=>({status:'unavailable',reason,retryAfterSeconds});
const finite=n=>typeof n==='number'&&Number.isFinite(n);
const angle=(a,b)=>Math.abs(((a-b+540)%360)-180);
function distance(a,b){const r=Math.PI/180,p=(b[1]-a[1])*r,q=(b[0]-a[0])*r;return 12742000*Math.asin(Math.min(1,Math.sqrt(Math.sin(p/2)**2+Math.cos(a[1]*r)*Math.cos(b[1]*r)*Math.sin(q/2)**2)));}
function bearing(a,b){const r=Math.PI/180,d=(b[0]-a[0])*r;return (Math.atan2(Math.sin(d)*Math.cos(b[1]*r),Math.cos(a[1]*r)*Math.sin(b[1]*r)-Math.sin(a[1]*r)*Math.cos(b[1]*r)*Math.cos(d))/r+360)%360;}
function validTrace(points,now){
 return Array.isArray(points)&&points.length>=3&&points.length<=12&&points.every((p,i)=>p&&['lat','lng','at','speed','accuracy','speedAccuracy','heading','headingAccuracy'].every(k=>finite(p[k]))&&
  Math.abs(p.lat)<=85&&Math.abs(p.lng)<=180&&p.mocked===false&&p.speed>=0&&p.speed<=100&&p.accuracy>=0&&p.accuracy<=15&&p.speedAccuracy>=0&&p.speedAccuracy<=2&&p.heading>=0&&p.heading<360&&p.headingAccuracy>=0&&p.headingAccuracy<=20&&
  now-p.at>=0&&now-p.at<=30000&&(!i||(p.at>points[i-1].at&&p.at-points[i-1].at<=10000&&distance([p.lng,p.lat],[points[i-1].lng,points[i-1].lat])<=100*(p.at-points[i-1].at)/1000+30)))&&
  now-points.at(-1).at<=5000&&points.at(-1).at-points[0].at>=2000&&points.at(-1).speed>=2;
}
function makeRequest(points,key){
 const url=new URL('https://api.tomtom.com/snapToRoads/1');
 url.search=new URLSearchParams({key,vehicleType:'PassengerCar',measurementSystem:'metric',offroadMargin:'20',fields:'{projectedPoints{geometry{coordinates},properties{routeIndex,snapResult}},route{geometry{coordinates},properties{id,elementType,confidence,speedLimits{value,unit,type}}}}'});
 return {url,body:JSON.stringify({points:points.map(p=>({type:'Feature',geometry:{type:'Point',coordinates:[p.lng,p.lat]},properties:{heading:p.heading,timestamp:new Date(p.at).toISOString()}}))})};
}
function limitKmh(value){
 if(!value||value.type!=='Maximum'||!Number.isInteger(value.value)||value.value<=0||value.condition||value.conditions||value.conditional)return null;
 const n=value.unit==='kmph'?value.value:value.unit==='mph'?value.value*1.609344:null;
 return n!==null&&n<=250?n:null;
}
function parseMatch(data,points,now){
 if(!Array.isArray(data?.route)||!Array.isArray(data.projectedPoints)||data.projectedPoints.length!==points.length)return unknown('unmatched');
 const recent=data.projectedPoints.slice(-3),inputs=points.slice(-3);
 for(let i=0;i<3;i++){
  const p=recent[i],xy=p.geometry?.coordinates,index=p.properties?.routeIndex,road=data.route[index];
  if(p.properties?.snapResult!=='Matched'||!Number.isInteger(index)||!Array.isArray(xy)||xy.length!==2||!xy.every(finite)||Math.abs(xy[0])>180||Math.abs(xy[1])>85||
   !road||road.properties?.elementType!=='Road'||!finite(road.properties.confidence)||road.properties.confidence<.95||road.properties.confidence>1||
   distance(xy,[inputs[i].lng,inputs[i].lat])>10)return unknown('ambiguous');
 }
 const a=recent[0].geometry.coordinates,b=recent[2].geometry.coordinates;
 if(distance(a,b)<10||angle(bearing(a,b),inputs[2].heading)>25)return unknown('direction');
 const road=data.route[recent[2].properties.routeIndex],p=road.properties,n=limitKmh(p.speedLimits);
 if(n===null||typeof p.id!=='string'||!p.id)return unknown('missing_limit');
 const last=points.at(-1),expiresAt=last.at+12000;
 if(now>=expiresAt)return unknown('stale');
 return {status:'available',kilometersPerHour:n,source:'TomTom',roadId:p.id,sampleAt:last.at,validUntil:expiresAt,latitude:last.lat,longitude:last.lng,heading:last.heading,applicabilityVerified:true,unambiguousMatch:true};
}
function createHandler({authenticate,reserve,fetchImpl=fetch,key=()=>process.env.TOMTOM_API_KEY,now=Date.now}){
 const cache=new Map();let unavailableUntil=0;
 return async(req,res)=>{
  res.setHeader('Cache-Control','no-store');
  if(req.method!=='POST')return res.status(405).json(unknown('method'));
  try{
   const uid=await authenticate(req);if(!uid)return res.status(401).json(unknown('authentication',60));
   const time=now(),points=req.body?.points;
   if(!validTrace(points,time))return res.status(400).json(unknown('gps_quality'));
   if(!key())return res.status(200).json(unknown('not_configured',300));
   if(time<unavailableUntil)return res.status(200).json(unknown('provider_unavailable',60));
   const hash=crypto.createHash('sha256').update(uid+JSON.stringify(points)).digest('hex'),cached=cache.get(hash);
   if(cached?.until>time)return res.status(200).json(cached.value);
   if(!await reserve(uid,time))return res.status(429).json(unknown('rate_limited',30));
   const request=makeRequest(points,key());
   const response=await fetchImpl(request.url,{method:'POST',headers:{'Content-Type':'application/json'},body:request.body,signal:AbortSignal.timeout(4000)});
   if(!response.ok){unavailableUntil=time+60000;return res.status(200).json(unknown('provider_unavailable',60));}
   const raw=await response.text();if(raw.length>1000000)return res.status(200).json(unknown('provider_response'));
   const result=parseMatch(JSON.parse(raw),points,now());
   for(const[k,v]of cache)if(v.until<=time)cache.delete(k);
   if(cache.size>=128)cache.delete(cache.keys().next().value);
   cache.set(hash,{until:time+5000,value:result});return res.status(200).json(result);
  }catch{return res.status(200).json(unknown('unavailable',30));}
 };
}
module.exports={validTrace,makeRequest,parseMatch,limitKmh,createHandler,distance,angle};

function createAuthenticate(admin,db){return async req=>{
 const bearer=req.headers.authorization||'';if(!bearer.startsWith('Bearer '))return null;
 let token;try{token=await admin.auth().verifyIdToken(bearer.slice(7),true);}catch{return null;}
 const profile=(await db.collection('users').doc(token.uid).get()).data();
 return profile&&!profile.deleted&&!profile.banned?token.uid:null;
};}
function createReserve(db,env=process.env){return (uid,now)=>db.runTransaction(async tx=>{
 const date=new Date(now).toISOString(), user=db.collection('_road_speed_limits').doc(uid),
  day=db.collection('_road_speed_budget').doc(date.slice(0,10)),month=db.collection('_road_speed_budget').doc(date.slice(0,7));
 const [u,d,m]=await Promise.all([tx.get(user),tx.get(day),tx.get(month)]),state=d.data()||{};
 const budget=Math.max(0,Math.min(100000,Number(env.TOMTOM_SPEED_LIMIT_DAILY_BUDGET??1000)||0));
 const monthly=Math.max(0,Math.min(2500,Number(env.TOMTOM_SPEED_LIMIT_MONTHLY_BUDGET??2500)||0));
 if(now-(u.data()?.lastAt||0)<5000||now-(state.lastAt||0)<250||(state.count||0)>=budget||(m.data()?.count||0)>=monthly)return false;
 tx.set(user,{lastAt:now});tx.set(day,{count:(state.count||0)+1,lastAt:now});tx.set(month,{count:(m.data()?.count||0)+1});return true;
});}
module.exports.createAuthenticate=createAuthenticate;
module.exports.createReserve=createReserve;
