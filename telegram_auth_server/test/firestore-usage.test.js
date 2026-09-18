const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');const fs=require('node:fs');
function fixture(fetch){const module={exports:{}};vm.runInNewContext(fs.readFileSync(require.resolve('../api/firestore-usage.js'),'utf8')+';module.exports.helpers={listTimeSeries,readDeltaMetric,startOfTodayIso};',{
 module,URL,Date,fetch,require:(id)=> id.includes('debug-access')?{debugAccessStatus:async()=>200}:id.includes('monitoring-config')?{monitoringConfig:()=>({projectId:'test',credentials:{}})}:{GoogleAuth:class {async getClient(){return {getAccessToken:async()=>({token:'test'})}}}},
});return module.exports;}
test('operation metrics use sum alignment, database resource and all pages',async()=>{
const urls=[];const h=fixture(async url=>{urls.push(new URL(url));return {ok:true,json:async()=>({timeSeries:[{points:[{value:{int64Value:urls.length===1?'7':'3'},interval:{endTime:'2026-09-18T12:00:00Z'}}]}],...(urls.length===1?{nextPageToken:'next'}:{})})}}).helpers;
const total=await h.readDeltaMetric({token:'test',projectId:'test',metricType:'firestore.googleapis.com/document/read_ops_count',startTime:'2026-09-18T00:00:00Z',endTime:'2026-09-18T12:00:00Z'});
assert.equal(total,10);assert.equal(urls.length,2);assert.equal(urls[1].searchParams.get('pageToken'),'next');
assert.equal(urls[0].searchParams.get('aggregation.perSeriesAligner'),'ALIGN_SUM');
assert.match(urls[0].searchParams.get('filter'),/resource.type="firestore.googleapis.com\/Database"/);
assert.ok(h.startOfTodayIso().endsWith('T00:00:00.000Z'));
});
test('missing Monitoring permission gives actionable error without secrets',async()=>{
const h=fixture(async()=>({ok:false,status:403})).helpers;
await assert.rejects(h.listTimeSeries({token:'SECRET',projectId:'test',metricType:'x',startTime:'a',endTime:'b',aligner:'ALIGN_SUM'}),e=>e.message.includes('roles/monitoring.viewer')&&!e.message.includes('SECRET'));
});
test('missing metric data is unavailable, never presented as zero usage',async()=>{
const handler=fixture(async()=>({ok:true,json:async()=>({})}));const res={status(c){this.code=c;return this},json(b){this.body=b;return this}};
await handler({method:'GET'},res);assert.equal(res.code,500);assert.match(res.body.error,/No Firestore metric samples/);
});
