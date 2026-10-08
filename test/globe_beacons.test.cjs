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
