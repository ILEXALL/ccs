const test=require('node:test');
const assert=require('node:assert/strict');
const {beaconDistance,beaconOpacity,beaconPlacement}=require('../assets/globe/beacons.js');
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

test('speed zoom retains low-speed scale and doubles distance at 100 km/h',()=>{
 const {speedFollowZoom}=require('../assets/globe/beacons.js');
 assert.equal(speedFollowZoom(16.35,0),16.35);
 assert.equal(speedFollowZoom(16.35,30/3.6),16.35);
 assert.ok(Math.abs(speedFollowZoom(16.35,100/3.6)-15.35)<1e-10);
 assert.equal(speedFollowZoom(16.35,NaN),16.35);
 let previous=16.35;
 for(let k=31;k<=150;k++){const z=speedFollowZoom(16.35,k/3.6);assert.ok(z<previous);assert.ok(previous-z<.025);previous=z;}
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
