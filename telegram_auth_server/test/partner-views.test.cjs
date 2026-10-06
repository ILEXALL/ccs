const {test}=require('node:test');
const assert=require('node:assert/strict');
const {recordPartnerView}=require('../lib/partner-views');
test('repeat and concurrent visits count once per account; another account adds one',async()=>{
 const docs=new Map([['partners/sponsor',{active:true}],['users/alice',{}],['users/bob',{}]]);
 let queue=Promise.resolve();
 const db={collection:c=>({doc:id=>({path:`${c}/${id}`})}),runTransaction:fn=>{
   const work=queue.then(()=>fn({get:async ref=>({exists:docs.has(ref.path),data:()=>docs.get(ref.path)}),
     create:(ref,data)=>{assert.ok(!docs.has(ref.path));docs.set(ref.path,data);},
     update:(ref,data)=>docs.set(ref.path,{...docs.get(ref.path),...data})}));
   queue=work.catch(()=>{});return work;
 }};
 assert.deepEqual(await Promise.all([recordPartnerView(db,'alice','sponsor'),recordPartnerView(db,'alice','sponsor')]),[1,1]);
 assert.equal(await recordPartnerView(db,'bob','sponsor'),2);
 assert.equal(await recordPartnerView(db,'alice','sponsor'),2);
 await assert.rejects(recordPartnerView(db,'missing','sponsor'));
 await assert.rejects(recordPartnerView(db,'alice','missing'));
 await assert.rejects(recordPartnerView(db,'alice','invalid/id'));
 assert.equal(docs.get('partners/sponsor').uniqueViews,2);
});
