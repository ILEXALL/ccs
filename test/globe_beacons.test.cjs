const test=require('node:test');
const assert=require('node:assert/strict');
const {beaconDistance,beaconOpacity,beaconPlacement}=require('../assets/globe/beacons.js');

test('all directions clear measured controls and speedometer at different screen sizes',()=>{
 const {beaconSafeBounds}=require('../assets/globe/beacons.js');
 for(const [width,height] of [[360,640],[430,932],[800,400]]) {
  for(const bottom of [84,116,160]) {
   const bounds=beaconSafeBounds(width,height,{top:84,bottom},true);
   const origin={x:width/2,y:(bounds.top+bounds.bottom)/2};
   for(let degree=0;degree<360;degree++) {
    const a=degree*Math.PI/180;
    const at=beaconPlacement(origin,{x:origin.x+Math.cos(a)*2000,y:origin.y+Math.sin(a)*2000},bounds);
    assert.ok(at);
    assert.ok(at.x>=bounds.left-1e-6 && at.x<=bounds.right+1e-6);
    assert.ok(at.y>=bounds.top-1e-6 && at.y<=bounds.bottom+1e-6);
    assert.ok(at.y+40<=height-bottom);
    assert.ok(at.y-60>=84);
   }
  }
 }
});
test('fade thresholds and monotonic proximity',()=>{
 assert.equal(beaconOpacity(2000),0);assert.equal(beaconOpacity(2500),0);
 assert.equal(beaconOpacity(500),1);assert.equal(beaconOpacity(0),1);
 assert.equal(beaconOpacity(1250),.5);
 assert.ok(beaconOpacity(600)>beaconOpacity(1600));
});
test('distances handle equator, same position and date line',()=>{
 assert.equal(beaconDistance([24,57],[24,57]),0);
 assert.ok(Math.abs(beaconDistance([0,0],[.01,0])-1111.95)<1);
 assert.ok(beaconDistance([179.999,0],[-179.999,0])<223);
});
test('visible markers get no beacon; offscreen directions intersect safe edges',()=>{
 const bounds={left:30,right:370,top:130,bottom:600},origin={x:200,y:400};
 assert.equal(beaconPlacement(origin,{x:250,y:300},bounds),null);
 assert.deepEqual(beaconPlacement(origin,{x:600,y:400},bounds),{x:370,y:400});
 assert.deepEqual(beaconPlacement(origin,{x:200,y:0},bounds),{x:200,y:130});
 assert.deepEqual(beaconPlacement(origin,{x:200,y:900},bounds),{x:200,y:600});
 assert.equal(beaconPlacement(origin,{x:NaN,y:0},bounds),null);
});

test('camera proximity fades only from 500m to 200m without changing spot range',()=>{
  assert.equal(beaconOpacity(501,'camera'),0);
  assert.equal(beaconOpacity(500,'camera'),0);
  assert.equal(beaconOpacity(350,'camera'),0.5);
  assert.equal(beaconOpacity(200,'camera'),1);
  assert.equal(beaconOpacity(0,'camera'),1);
  assert.equal(beaconOpacity(500,'spot'),1);
});

test('SOS and police use independent smooth distance ranges',()=>{
 for (const [kind,start,end] of [['sos',5000,1000],['police',2000,500]]) {
  assert.equal(beaconOpacity(start+1,kind),0);
  assert.equal(beaconOpacity(start,kind),0);
  assert.equal(beaconOpacity((start+end)/2,kind),0.5);
  assert.equal(beaconOpacity(end,kind),1);
  assert.equal(beaconOpacity(0,kind),1);
  let previous=0;
  for(let d=start;d>=end;d-=10){const opacity=beaconOpacity(d,kind);assert.ok(opacity>=previous);previous=opacity;}
 }
});

test('speed zoom retains low-speed scale and triples distance at 100 km/h',()=>{
 const {speedFollowZoom}=require('../assets/globe/beacons.js');
 assert.equal(speedFollowZoom(16.35,0),16.35);
 assert.equal(speedFollowZoom(16.35,30/3.6),16.35);
 assert.ok(Math.abs(speedFollowZoom(16.35,100/3.6)-(16.35-Math.log2(3)))<1e-10);
 assert.equal(speedFollowZoom(16.35,NaN),16.35);
 let previous=16.35;
 for(let k=31;k<=150;k++){const z=speedFollowZoom(16.35,k/3.6);assert.ok(z<previous);assert.ok(previous-z<.05);previous=z;}
});

test('radar attention follows driving bearing, not map rotation, and stops at rest',()=>{
 const {cameraAhead}=require('../assets/globe/beacons.js');
 assert.equal(cameraAhead([24,57],[24,57.003],0,15),true);
 assert.equal(cameraAhead([24,57],[24,57.003],359,15),true);
 assert.equal(cameraAhead([24,57],[24,56.997],0,15),false);
 assert.equal(cameraAhead([24,57],[24.003,57],0,15),false);
 assert.equal(cameraAhead([24,57],[24,57.003],0,0),false);
 assert.equal(cameraAhead([24,57],[24,57.003],NaN,15),false);
});

test('colocated people collapse with exact membership and split as they move apart',()=>{
 const {groupPeopleBeacons}=require('../assets/globe/beacons.js');
 const person=(id,x)=>({properties:{kind:'live',id,label:id},geometry:{coordinates:[x,0]}});
 const spot={properties:{kind:'spot',id:'spot'},geometry:{coordinates:[0,0]}};
 const result=groupPeopleBeacons([person('b',.0001),person('a',0),person('c',.01),spot]);
 assert.equal(result.length,3);assert.equal(result[0],spot);
 const group=result.find(f=>f.properties.count===2);
 assert.deepEqual(group.properties.memberIds,['a','b']);assert.equal(group.properties.label,'a, b');
 assert.equal(groupPeopleBeacons([person('a',0),person('b',.01)]).length,2);
});

test('beacon direction follows the near-ground ray when a far projection flips',()=>{
 const {beaconScreenDirection}=require('../assets/globe/beacons.js');
 const project=([x,y])=>({x:200+x*100,y:400+(Math.abs(y)>.01?y:-y)*100});
 const ray=beaconScreenDirection([0,0],[0,1],project);
 assert.ok(ray.dy<0);assert.equal(ray.inFront,false);
 assert.deepEqual(beaconPlacement({x:200,y:400},{x:200+ray.dx*1000,y:400+ray.dy*1000},{left:30,right:370,top:100,bottom:650}),{x:200,y:100});
 assert.equal(beaconScreenDirection([0,0],[0,0],project),null);
 assert.equal(beaconScreenDirection([0,0],[NaN,0],project),null);
});
