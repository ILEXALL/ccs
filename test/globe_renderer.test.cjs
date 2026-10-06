const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function fixture() {
  const handlers={}, messages=[], moves=[], sources={}, layers=[], paints=[], layouts=[], timers=new Set(), frames=new globalThis.Map();
  let frameId=0;
  class Map {
    constructor() {this.zoom=1;}
    addControl() {}
    on(name,...args) {handlers[name+(args.length===2?':'+args[0]:'')]=args.at(-1);}
    setStyle(url) {this.style=url;layers.length=0;delete sources.ccs;}
    setProjection(p) {this.projection=p;}
    setPaintProperty(...args) {paints.push(args);}
    setLayoutProperty(...args) {layouts.push(args);}
    getStyle() {return {layers:[]};}
    addSource(id,source) {sources[id]={...source,setData(d){this.data=d;}};}
    getSource(id) {return sources[id];}
    addLayer(layer) {layers.push(layer);}
    queryRenderedFeatures(point) {return point;}
    getZoom() {return this.zoom;}
    jumpTo(move) {moves.push(move);}
    easeTo(move) {moves.push(move);}
    fitBounds(bounds, options) {moves.push({bounds,...options});}
  }
  let clock=0;
  const touches={};
  const surface={addEventListener:(type,fn)=>{touches[type]=fn;}};
  const context={performance:{now:()=>clock},requestAnimationFrame:fn=>{frames.set(++frameId,fn);return frameId;},cancelAnimationFrame:id=>frames.delete(id),Date:{now:()=>clock},setInterval:fn=>{timers.add(fn);return fn;},clearInterval:fn=>timers.delete(fn),window:{CcsGlobe:{postMessage:m=>messages.push(JSON.parse(m))}},document:{getElementById:()=>({})},maplibregl:{Map,NavigationControl:class{}}};
  context.document.getElementById=id=>id==='map'?surface:{};
  vm.runInNewContext(fs.readFileSync('assets/globe/globe.js','utf8'),context);
  return {...context,touches,handlers,messages,moves,sources,layers,paints,layouts,timers,setTime:t=>clock=t, tick:t=>{clock=t;const pending=[...frames.values()];frames.clear();pending.forEach(fn=>fn(t));}, frames};
}
test('data arriving before map load survives; replacements remove expired markers',()=>{
  const f=fixture(), data={type:'FeatureCollection',features:[{properties:{kind:'spot',id:'one',label:'</script><script>bad()</script>'},geometry:{type:'Point',coordinates:[24,57]}}]};
  f.window.ccsSetFeatures(data); f.handlers['style.load']();
  assert.equal(f.sources.ccs.data,data);
  assert.equal(f.messages[0].type,'ready');
  const empty={type:'FeatureCollection',features:[]};
  f.window.ccsSetFeatures(empty); assert.equal(f.sources.ccs.data,empty);
});
test('live position updates follow only after opt-in and stop after a map gesture',()=>{
  const f=fixture(); f.handlers['style.load']();
  const positions=n=>({type:'FeatureCollection',features:[{properties:{kind:'self'},geometry:{coordinates:[n,57]}}]});
  f.window.ccsSetFeatures(positions(24)); assert.equal(f.moves.length,0);
  f.window.ccsFollow(); assert.equal(f.moves.length,1);
  f.window.ccsSetFeatures(positions(25)); assert.equal(f.moves.length,2);
  assert.equal(f.moves[1].center[0],25);
  f.handlers.dragstart(); f.window.ccsSetFeatures(positions(26)); assert.equal(f.moves.length,2);
});
test('taps send a selection, never content execution, and self marker does not select',()=>{
  const f=fixture(); f.handlers['style.load']();
  f.handlers.click({point:[{properties:{kind:'spot',id:'one'}},{properties:{kind:'spot',id:'one'}}]});
  assert.deepEqual(f.messages[1],{type:'select',kind:'spot',id:'one'});
  f.handlers.click({point:[{properties:{kind:'self',id:''}}]});
  assert.equal(f.messages.length,2);
});
test('all spots are retained and icon placement cannot discard dense neighbors',()=>{
  const f=fixture(); f.handlers['style.load']();
  const features=Array.from({length:600},(_,id)=>({properties:{kind:'spot',id:String(id),icon:'assets/spot_icons/photo.png',color:'#9b35ff',tint:false,event:false},geometry:{type:'Point',coordinates:[24+id/100000,57]}}));
  f.window.ccsSetFeatures({type:'FeatureCollection',features});
  assert.equal(f.sources.ccs.data.features.length,600);
  const icons=f.layers.find(l=>l.id==='ccs-spot-icons');
  assert.equal(icons.minzoom,11.25);
  assert.equal(icons.layout['icon-allow-overlap'],true);
  assert.equal(icons.layout['icon-ignore-placement'],true);
  assert.equal(f.layers.find(l=>l.id==='ccs-points').maxzoom,icons.minzoom);
  assert.equal(f.layers.find(l=>l.id==='ccs-labels').layout['text-font'][0],'Noto Sans Regular');
  assert.equal(f.sources.ccs.cluster,undefined);
});

test('style changes restore current data and use light artwork without resetting camera',()=>{
  const f=fixture(); f.handlers['style.load']();
  f.window.ccsSetStyle('positron');
  const data={type:'FeatureCollection',features:[{properties:{kind:'self',heading:123},geometry:{coordinates:[24,57]}}]};
  f.window.ccsSetFeatures(data);
  f.handlers['style.load']();
  assert.equal(f.sources.ccs.data,data);
  assert.equal(f.moves.length,0);
  assert.match(JSON.stringify(f.layers.find(l=>l.id==='ccs-spot-icons').layout['icon-image']),/lightIcon/);
  const arrow=f.layers.find(l=>l.id==='ccs-self');
  assert.equal(arrow.layout['icon-image'],'ccs-self-arrow');
  assert.equal(arrow.layout['icon-rotation-alignment'],'map');
  f.window.ccsSetStyle('dark'); f.handlers['style.load']();
  assert.doesNotMatch(JSON.stringify(f.layers.find(l=>l.id==='ccs-spot-icons').layout['icon-image']),/lightIcon/);
  f.handlers.click({point:[]});
  assert.equal(f.messages.at(-1).type,'clear');
});

 test('native navigation requests apply once and route bounds use both endpoints',()=>{
  const f=fixture(); f.handlers['style.load']();
  const frame={type:'FeatureCollection',features:[],camera:{revision:1,center:[24,57],zoom:16,bearing:45}};
  f.window.ccsSetFeatures(frame); f.window.ccsSetFeatures(frame);
  assert.equal(f.moves.length,1); assert.equal(f.moves[0].bearing,45);
  f.window.ccsSetFeatures({...frame,camera:{revision:2,bounds:[[24,57],[25,58]]}});
  assert.equal(f.moves.length,2); assert.equal(JSON.stringify(f.moves[1].bounds),JSON.stringify([[24,57],[25,58]]));
 });
 test('world control exits native following and pin selection reports coordinates',()=>{
  const f=fixture(); f.handlers['style.load'](); f.window.ccsWorld();
  assert.equal(f.messages.at(-1).type,'gesture');
  f.handlers.click({point:[],lngLat:{lat:57,lng:24}});
  assert.deepEqual(f.messages.at(-2),{type:'pick',lat:57,lng:24});
  assert.ok(f.layers.find(l=>l.id==='ccs-restricted'));
  assert.ok(f.layers.find(l=>l.id==='ccs-pin'));
 });

test('pins use the original glyph and tip anchoring rather than circle layers',()=>{
  const f=fixture(); f.handlers['style.load'](); const pin=f.layers.find(l=>l.id==='ccs-pin');
  assert.equal(pin.type,'symbol'); assert.equal(pin.layout['icon-anchor'],'bottom');
  assert.equal(pin.layout['icon-size'],56/64);
});
test('police alternates blue/red, SOS pulses, hidden views and removed alerts stop timers',()=>{
  const f=fixture(); f.handlers['style.load']();
  const data={type:'FeatureCollection',features:[{properties:{kind:'police'},geometry:{coordinates:[24,57]}}]};
  f.window.ccsSetFeatures(data); assert.equal(f.timers.size,1);
  assert.ok(f.paints.some(x=>x[0]==='ccs-police-core' && x[2]==='rgb(21,101,255)'));
  f.setTime(3000); [...f.timers][0]();
  assert.ok(f.paints.some(x=>x[0]==='ccs-police-core' && x[2]==='rgb(255,45,85)'));
  assert.deepEqual(f.layouts.at(-1),['ccs-police-badge','icon-image','ccs-police-16']);
  assert.ok(f.paints.some(x=>x[0]==='ccs-sos-glow' && x[2]===0.56));
  f.window.ccsSetActive(false); assert.equal(f.timers.size,0);
  f.window.ccsSetActive(true); assert.equal(f.timers.size,1);
  f.window.ccsSetFeatures({type:'FeatureCollection',features:[]}); assert.equal(f.timers.size,0);
  assert.equal(f.layers.find(l=>l.id==='ccs-police-badge').minzoom,14.2);
  assert.equal(f.layers.find(l=>l.id==='ccs-sos-badge').layout['icon-image'],'ccs-sos');
});

test('live users render their car artwork with course rotation',()=>{
 const f=fixture(); f.handlers['style.load']();
 const cars=f.layers.find(l=>l.id==='ccs-live-cars');
 assert.equal(cars.type,'symbol'); assert.equal(cars.layout['icon-rotation-alignment'],'map');
 assert.match(JSON.stringify(cars.layout['icon-image']),/car_green/);
 assert.ok(!f.layers.some(l=>l.id==='ccs-live-points'));
});
test('motion interpolates arrow and camera together without changing the spots source',()=>{
 const f=fixture(); f.handlers['style.load'](); const spots=f.sources.ccs.data;
 f.window.ccsSetMotion({position:[24,57],heading:350,following:true,zoom:16}); f.tick(100);
 f.window.ccsSetMotion({position:[24.001,57.001],heading:10,following:true,zoom:16}); f.tick(150);
 const marker=f.sources['ccs-motion'].data.features[0];
 assert.ok(marker.geometry.coordinates[0]>24 && marker.geometry.coordinates[0]<24.001);
 assert.ok(marker.properties.heading>350 && marker.properties.heading<370);
 assert.deepEqual(f.moves.at(-1).center,marker.geometry.coordinates);
 assert.equal(f.sources.ccs.data,spots);
 f.handlers.dragstart(); const moves=f.moves.length; f.tick(200);
 assert.equal(f.moves.length,moves);
 f.window.ccsSetMotion({position:[25,58],heading:10,following:false,zoom:16});
 f.window.ccsSetActive(false); assert.equal(f.frames.size,0);
});
test('motion keeps advancing between irregular packets and stops its loop when stale',()=>{
 const f=fixture();f.handlers['style.load']();
 f.window.ccsSetMotion({position:[24,57],heading:90,following:true,zoom:16});f.tick(16);
 f.setTime(100);f.window.ccsSetMotion({position:[24.00003,57],heading:90,following:true,zoom:16});
 let previous=24;
 for(let t=116;t<=244;t+=16){
   f.tick(t);const x=f.sources['ccs-motion'].data.features[0].geometry.coordinates[0];
   assert.ok(x>previous,'movement must not stop at the 100 ms packet boundary');previous=x;
 }
 f.tick(1200);assert.equal(f.frames.size,0);
});
test('manual rotation survives delayed follow packets until an explicit follow tap',()=>{
 const f=fixture();f.handlers['style.load']();
 const packet={position:[24,57],heading:90,following:true,zoom:16,followRevision:1};
 f.window.ccsSetMotion(packet);f.tick(16);
 f.handlers['rotatestart']({originalEvent:{}});
 const count=f.moves.length;
 f.window.ccsSetMotion(packet);f.tick(32);
 assert.equal(f.moves.length,count);
 f.window.ccsSetFeatures({type:'FeatureCollection',features:[],camera:{revision:50,center:[24,57],zoom:16,bearing:0}});
 assert.equal(f.moves.at(-1).bearing,undefined);
 f.window.ccsSetMotion({...packet,followRevision:2});f.tick(48);
 assert.equal(f.moves.at(-1).bearing,90);
});
test('two-finger pinch exits follow before zoomstart and ignores queued camera updates',()=>{
 const f=fixture();f.handlers['style.load']();
 const packet={position:[24,57],heading:45,following:true,zoom:16,followRevision:1};
 f.window.ccsSetMotion(packet);f.tick(16);
 const count=f.moves.length;
 f.touches.touchstart({touches:[{},{}]});
 assert.equal(f.messages.at(-1).type,'gesture');
 f.handlers.zoomstart({});
 f.window.ccsSetMotion(packet);f.tick(32);
 f.window.ccsSetFeatures({features:[],camera:{revision:1,center:[24,57],zoom:16,bearing:45}});
 assert.equal(f.moves.length,count);
 f.touches.touchend({touches:[]});
 f.window.ccsSetMotion({...packet,followRevision:2});f.tick(48);
 assert.equal(f.moves.length,count+1);
});
test('route preview sorts bounds and crosses the date line by the shortest arc',()=>{
 const f=fixture();f.handlers['style.load']();
 f.window.ccsSetFeatures({features:[],camera:{revision:1,bounds:[[25,58],[24,57]]}});
 assert.equal(JSON.stringify(f.moves.at(-1).bounds),JSON.stringify([[24,57],[25,58]]));
 assert.equal(f.moves.at(-1).bearing,0);
 assert.equal(f.moves.at(-1).pitch,0);
 f.window.ccsSetFeatures({features:[],camera:{revision:2,bounds:[[179,58],[-179,57]]}});
 assert.equal(JSON.stringify(f.moves.at(-1).bounds),JSON.stringify([[179,57],[181,58]]));
});
