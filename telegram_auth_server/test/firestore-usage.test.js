const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');const fs=require('node:fs');
function fixture(fetch){const module={exports:{}};vm.runInNewContext(fs.readFileSync(require.resolve('../api/firestore-usage.js'),'utf8')+';module.exports.helpers={listTimeSeries,readDeltaMetric,startOfTodayIso,reportingPeriod};',{
 module,URL,Date,fetch,require:(id)=> id.includes('firestore-cost')?require('../lib/firestore-cost'):id.includes('debug-access')?{debugAccessStatus:async()=>200}:id.includes('monitoring-config')?{monitoringConfig:()=>({projectId:'test',credentials:{}})}:{GoogleAuth:class {async getClient(){return {getAccessToken:async()=>({token:'test'})}}}},
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


test('calendar periods start at UTC midnight, weeks on Monday and months on day 1',()=>{
 const {reportingPeriod}=fixture(()=>{}).helpers;
 const now=new Date('2026-03-01T23:59:00Z');
 assert.equal(reportingPeriod('day',now).startTime,'2026-03-01T00:00:00.000Z');
 assert.equal(reportingPeriod('week',now).startTime,'2026-02-23T00:00:00.000Z');
 assert.equal(reportingPeriod('month',now).startTime,'2026-03-01T00:00:00.000Z');
 assert.equal(reportingPeriod('week',new Date('2026-01-01T10:00:00Z')).startTime,'2025-12-29T00:00:00.000Z');
 assert.equal(reportingPeriod('week',new Date('2026-03-02T00:00:00Z')).startTime,'2026-03-02T00:00:00.000Z');
 assert.equal(reportingPeriod('month',now).endTime,now.toISOString());
 assert.throws(()=>reportingPeriod('year',now),/Invalid/);
});

test('selected period is applied to read/write/delete totals and breakdown, gauges stay recent',async()=>{
 const urls=[];const handler=fixture(async url=>{urls.push(new URL(url));return {ok:true,json:async()=>({timeSeries:[{points:[{value:{int64Value:'3'},interval:{endTime:new Date().toISOString()}}]}]})}});
 const res={status(c){this.code=c;return this},json(b){this.body=b;return this}};
 await handler({method:'GET',query:{period:'month'}},res);
 assert.equal(res.code,200);assert.equal(res.body.periodKey,'month');
 for(const u of urls.filter(u=>u.searchParams.get('filter').includes('/document/'))) assert.equal(u.searchParams.get('interval.startTime'),new Date(res.body.period.startMillis).toISOString());
 assert.equal(new Date(res.body.period.startMillis).getUTCDate(),1);
 await handler({method:'GET',query:{period:'invalid'}},res);assert.equal(res.code,400);
});
