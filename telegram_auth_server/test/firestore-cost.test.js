const test=require('node:test');
const assert=require('node:assert/strict');
const {estimateOperations}=require('../lib/firestore-cost');
const start=Date.parse('2026-10-01T00:00:00Z');
const series=(points)=>[{points:points.map(([time,count])=>({interval:{endTime:time},value:{int64Value:String(count)}}))}];
test('EUR estimate subtracts free allowances per Pacific day without carrying unused quota',()=>{
 const result=estimateOperations({reads:series([['2026-10-01T12:00:00Z',100000],['2026-10-02T12:00:00Z',1000]]),writes:series([['2026-10-01T12:00:00Z',30000]]),deletes:series([['2026-10-01T12:00:00Z',25000]])},start);
 assert.equal(result.breakdown.reads.billable,50000);
 assert.equal(result.breakdown.writes.billable,10000);
 assert.equal(result.breakdown.deletes.billable,5000);
 assert.ok(Math.abs(result.amountEur-(50000*281+10000*835+5000*96)/1e9)<1e-12);
});
test('free quota consumed before the UTC month boundary is respected',()=>{
 const result=estimateOperations({reads:series([['2026-09-30T23:00:00Z',60000],['2026-10-01T01:00:00Z',5000],['2026-10-01T08:00:00Z',1000]])},start);
 assert.equal(result.breakdown.reads.billable,5000);
});
test('zero usage is zero, but missing samples are unavailable',()=>{
 assert.equal(estimateOperations({reads:series([['2026-10-01T12:00:00Z',0]])},start).amountEur,0);
 assert.throws(()=>estimateOperations({},start),/unavailable/);
});
