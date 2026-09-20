const test=require('node:test'),assert=require('node:assert/strict');
const {fixture}=require('./support');
const {weekKeyFor}=require('../lib/xp/xp-engine');
async function request(f,body={}) {
 const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;},setHeader(){}};
 await f.load('../handlers/xp-leaderboard.js')({method:'POST',headers:{authorization:'Bearer tester'},body},res);
 return res;
}
for(const period of ['all_time','weekly']) test(period+': country scopes results, ranks, search and cursors',async()=>{
 const f=fixture({'users/tester':{country:'Latvija'}}),week=weekKeyFor(new Date());
 for(let i=0;i<25;i++) {
  const uid='u'+i;
  f.rows.set('users/'+uid,{country:i%2===0?'Latvia':'Germany',username:'Driver'+i});
  f.rows.set('xp_user_stats/'+uid,{xpTotal:1000-i});
  f.rows.set('xp_user_weeks/'+uid+'_'+week,{userId:uid,weekKey:week,confirmedXp:1000-i});
 }
 let res=await request(f,{period,country:'DE',countryCode:'DE'});
 assert.equal(res.code,200);assert.equal(res.body.result.countryCode,'LV');
 assert.equal(res.body.result.entries.length,10);
 assert.ok(res.body.result.entries.every(e=>e.country==='Latvia'));
 assert.deepEqual(Array.from(res.body.result.entries,e=>e.rank),[1,2,3,4,5,6,7,8,9,10]);
 const cursor=res.body.result.nextCursor;
 res=await request(f,{period,cursor});assert.equal(res.body.result.entries.length,3);
 res=await request(f,{period,search:'Driver1'});assert.ok(res.body.result.entries.every(e=>e.country==='Latvia'));
 f.rows.get('users/tester').country='DE';
 res=await request(f,{period,cursor});assert.equal(res.code,409);
 res=await request(f,{period});assert.ok(res.body.result.entries.every(e=>e.country==='Germany'));
 f.rows.get('users/tester').country='';res=await request(f,{period});assert.equal(res.body.result.entries.length,0);
});
