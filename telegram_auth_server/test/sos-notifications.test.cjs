const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
function fixture(overrides = {}, count = 205) {
  const now = Date.now();
  const report = {uid:'owner',status:'active',lat:0,lng:0,createdAt:now-1000,expiresAt:now+60000,...overrides};
  const near = {lat:0,lng:0.01,updatedAt:now,expiresAt:now+60000};
  const locations = Array.from({length:count},(_,i)=>({id:`u${i}`,data:()=>near}));
  locations.push({id:'owner',data:()=>near},
    {id:'far',data:()=>({...near,lng:1})},
    {id:'expired',data:()=>({...near,expiresAt:now-1})},
    {id:'invalid',data:()=>({...near,lat:NaN})},
    {id:'mock',data:()=>({...near,isMocked:true})},
    {id:'future',data:()=>({...near,updatedAt:now+60000})});
  const claims = new Set(), calls = [];
  const db = {collection:name=>({
    doc:id=>({get:async()=>({data:()=>report}),create:async()=>{
      if(claims.has(id))throw Object.assign(new Error('duplicate'),{code:6});claims.add(id);
    }}),
    where:(_field,_op,since)=>{assert.ok(now-since <= 300001);let start=0,limit=200;
      const query={orderBy:()=>query,limit:n=>{limit=n;return query;},startAfter:doc=>{start=locations.indexOf(doc)+1;return query;},
        get:async()=>({docs:locations.slice(start,start+limit)})};return query;},
  })};
  const firestore=()=>db;firestore.Timestamp={fromMillis:v=>v};firestore.FieldValue={serverTimestamp:()=>now};
  const context=vm.createContext({console,admin:{apps:[true],firestore},crypto:require('node:crypto'),calls});
  const source=fs.readFileSync(path.join(__dirname,'../api/push-notification.js'),'utf8')
    .replace(/^import .*;\r?\n/gm,'').replace(/export default /g,'').replace(/export /g,'');
  vm.runInContext(source+`
sendPushToUser=async options=>{if(!await claimDelivery(options.deliveryKey,options.userId))return 0;calls.push(options);return 1;};`,context);
  return {context,calls,report};
}
test('SOS pages every eligible nearby user and retries without duplicate pushes',async()=>{
 const f=fixture();await f.context.handleSosCreated('owner',{reportId:'owner',recipientUserIds:['far']});
 assert.equal(f.calls.length,205);assert.equal(f.calls[0].data.type,'sos_created');
 assert.equal(f.calls[0].settingName,'sosNotifications');
 assert.equal(f.context.settingEnabled({},f.calls[0].settingName),true);
 assert.equal(f.context.settingEnabled({settings:{sosNotifications:false}},f.calls[0].settingName),false);
 await f.context.handleSosCreated('owner',{reportId:'owner'});assert.equal(f.calls.length,205);
 f.report.createdAt+=1;await f.context.handleSosCreated('owner',{reportId:'owner'});assert.equal(f.calls.length,410);
});
test('only the owner of a recent active SOS can dispatch',async()=>{
 for(const overrides of [{uid:'other'},{status:'closed'},{createdAt:Date.now()-600000},{expiresAt:1},{lat:91}]){
  const f=fixture(overrides);await f.context.handleSosCreated('owner',{reportId:'owner'});assert.equal(f.calls.length,0);
 }
 const f=fixture();await f.context.handleSosCreated('other',{reportId:'owner'});assert.equal(f.calls.length,0);
});
test('10 km boundary uses geodesic distance, including the date line',()=>{
 const {context:c}=fixture();
 assert.ok(c.sosDistanceMeters({lat:0,lng:0},{lat:0,lng:9999/6371000*180/Math.PI})<10000);
 assert.ok(c.sosDistanceMeters({lat:0,lng:0},{lat:0,lng:10001/6371000*180/Math.PI})>10000);
 assert.ok(c.sosDistanceMeters({lat:0,lng:179.99},{lat:0,lng:-179.99})<3000);
});
