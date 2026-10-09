const test=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm');
function fixture(){
 let id=0;const native=new Map();const window={requestAnimationFrame:fn=>{native.set(++id,fn);return id},cancelAnimationFrame:id=>native.delete(id)};
 vm.runInNewContext(fs.readFileSync('assets/globe/frame_scheduler.js','utf8'),{window,Map,setTimeout});
 return {window,native,tick(now){const tasks=[...native.values()];native.clear();for(const fn of tasks)fn(now)}};
}
test('120 Hz display is limited to 30 follow frames and 60 manual frames',()=>{
 for(const [follow,expected] of [[true,30],[false,60]]){
  const f=fixture();f.window.ccsFrameBudget(follow);let count=0;
  const loop=()=>{count++;f.window.requestAnimationFrame(loop)};f.window.requestAnimationFrame(loop);
  for(let i=0;i<120;i++)f.tick(i*1000/120);
  assert.equal(count,expected);
 }
});
test('frame budget switches without duplicate loops and stops while hidden',()=>{
 const f=fixture();let count=0;const loop=()=>{count++;f.window.requestAnimationFrame(loop)};
 f.window.ccsFrameBudget(true);f.window.requestAnimationFrame(loop);f.tick(0);f.tick(16.67);assert.equal(count,1);
 f.window.ccsFrameBudget(false);f.tick(16.67);assert.equal(count,2);assert.equal(f.native.size,1);
 f.window.ccsFrameBudget(false,false);assert.equal(f.native.size,0);f.tick(100);assert.equal(count,2);
 f.window.ccsFrameBudget(false,true);f.tick(110);assert.equal(count,3);
});
test('callbacks share a frame; cancellation works before and within a batch',()=>{
 const f=fixture(), calls=[];
 let cancelled;f.window.requestAnimationFrame(()=>{calls.push('first');f.window.cancelAnimationFrame(cancelled)});
 cancelled=f.window.requestAnimationFrame(()=>calls.push('cancelled'));
 const other=f.window.requestAnimationFrame(()=>calls.push('other'));f.window.cancelAnimationFrame(other);
 assert.equal(f.native.size,1);f.tick(0);assert.deepEqual(calls,['first']);assert.equal(f.native.size,0);
});
test('scheduler is installed before MapLibre captures requestAnimationFrame',()=>{
 const html=fs.readFileSync('assets/globe/index.html','utf8');assert.ok(html.indexOf('frame_scheduler.js')<html.indexOf('src="maplibre-gl.js"'));
});
