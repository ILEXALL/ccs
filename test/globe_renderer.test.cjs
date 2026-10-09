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
    getBearing() {return this.bearing || 0;}
    getCanvas() {return {clientWidth:400,clientHeight:800};}
    jumpTo(move) {moves.push(move);}
    easeTo(move) {moves.push(move);}
    fitBounds(bounds, options) {moves.push({bounds,...options});}
  }
  let clock=0;
  const touches={};
  const surface={addEventListener:(type,fn)=>{touches[type]=fn;}};
  const context={performance:{now:()=>clock},requestAnimationFrame:fn=>{frames.set(++frameId,fn);return frameId;},cancelAnimationFrame:id=>frames.delete(id),Date:{now:()=>clock},setInterval:fn=>{timers.add(fn);return fn;},clearInterval:fn=>timers.delete(fn),window:{CcsGlobe:{postMessage:m=>messages.push(JSON.parse(m))}},document:{getElementById:()=>({})},maplibregl:{Map,NavigationControl:class{}}};
  context.document.getElementById=id=>id==='map'?surface:{};
  vm.runInNewContext(fs.readFileSync('assets/globe/beacons.js','utf8'),context);
  vm.runInNewContext(fs.readFileSync('assets/globe/globe.js','utf8'),context);
  return {...context,run:code=>vm.runInNewContext(code,context),touches,handlers,messages,moves,sources,layers,paints,layouts,timers,setTime:t=>clock=t, tick:t=>{clock=t;const pending=[...frames.values()];frames.clear();pending.forEach(fn=>fn(t));}, frames};
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
test('one tap exits route preview without selecting a marker or moving the camera',()=>{
  const f=fixture(); f.handlers['style.load']();
  f.window.ccsSetFeatures({type:'FeatureCollection',routePreview:true,features:[]});
  const moves=f.moves.length;
  f.handlers.click({lngLat:{lat:57,lng:24},point:[{properties:{kind:'spot',id:'target'}}]});
  assert.deepEqual(f.messages.at(-1),{type:'dismissRoute'});
  assert.equal(f.messages.some(m=>m.type==='select'||m.type==='pick'),false);
  assert.equal(f.moves.length,moves);
  f.window.ccsSetFeatures({type:'FeatureCollection',routePreview:false,features:[]});
  f.handlers.click({point:[{properties:{kind:'spot',id:'other'}}]});
  assert.deepEqual(f.messages.at(-1),{type:'select',kind:'spot',id:'other'});
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
  assert.equal(f.sources.ccs.data.features.length,0);
  assert.equal(f.sources['ccs-motion'].data.features[0].properties.heading,123);
  assert.equal(f.moves.length,0);
  assert.match(JSON.stringify(f.layers.find(l=>l.id==='ccs-spot-icons').layout['icon-image']),/lightIcon/);
  const arrow=f.layers.find(l=>l.id==='ccs-self');
  assert.equal(arrow.layout['icon-image'],'ccs-self-arrow');
  assert.equal(arrow.layout['icon-rotation-alignment'],'viewport');
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
 assert.equal(cars.type,'symbol'); assert.equal(cars.layout['icon-rotation-alignment'],'viewport');
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

test('follow camera anchors the driver below center without retaining padding',()=>{
 const f=fixture();f.handlers['style.load']();
 f.window.ccsSetMotion({position:[24,57],heading:90,following:true,zoom:16,followRevision:1});f.tick(16);
 assert.equal(JSON.stringify(f.moves.at(-1).offset),JSON.stringify([0,144]));
 assert.equal(f.moves.at(-1).duration,0);
 assert.equal(f.moves.at(-1).padding,0);
 const count=f.moves.length;
 f.handlers.dragstart();
 f.window.ccsSetMotion({position:[24.001,57],heading:90,following:true,zoom:16,followRevision:1});f.tick(32);
 assert.equal(f.moves.length,count);
});

test('cameras stay at close zoom across style reload and can be selected',()=>{
  const f=fixture(); f.handlers['style.load']();
  const camera={type:'Feature',properties:{kind:'camera',id:'osm-node-123',icon:'ccs-speed-camera'},geometry:{type:'Point',coordinates:[24.1,56.9]}};
  f.window.ccsSetFeatures({type:'FeatureCollection',features:[camera]});
  for (let i=0;i<2;i++) {
    const layer=f.layers.find(l=>l.id==='ccs-cameras');
    assert.equal(layer.minzoom,13);
    assert.equal(layer.paint['icon-opacity'].at(-2),14.5);
    assert.equal(layer.paint['icon-opacity'].at(-1),1);
    assert.equal(layer.layout['icon-image'],'ccs-speed-camera');
    assert.equal(f.sources.ccs.data.features[0].properties.id,'osm-node-123');
    if(!i){ f.window.ccsSetStyle('positron'); f.handlers['style.load'](); }
  }
  f.handlers.click({point:[camera]});
  assert.deepEqual(f.messages.at(-1),{type:'select',kind:'camera',id:'osm-node-123'});
  f.window.ccsSetFeatures({type:'FeatureCollection',features:[]});
  assert.equal(f.sources.ccs.data.features.length,0);
});

test('bundled Latvia camera snapshot has real unique coordinates and licensing',()=>{
  const data=JSON.parse(fs.readFileSync('assets/globe/speed_cameras_lv.json','utf8'));
  assert.equal(data.region,'Latvia');
  assert.ok(data.cameras.length>0);
  assert.equal(new Set(data.cameras.map(c=>c.id)).size,data.cameras.length);
  for(const c of data.cameras){
    assert.match(c.id,/^osm-node-\d+$/);
    assert.ok(Number.isFinite(c.lat)&&c.lat>55&&c.lat<59);
    assert.ok(Number.isFinite(c.lon)&&c.lon>20&&c.lon<29);
    assert.equal(c.maxspeed,undefined);
  }
  assert.match(data.attribution,/OpenStreetMap/);
  assert.match(data.license,/odbl/);
});

test('offscreen SOS and police render report artwork, animate and open their cards',()=>{
 const f=fixture();
 const nodes=[];
 function element(){return {style:{setProperty(){}},dataset:{},children:[],appendChild(child){this.children.push(child);this.firstChild=this.children[0];this.lastChild=child;},addEventListener(name,fn){this[name]=fn;},getBoundingClientRect(){},getContext(){return {putImageData(){}};},setAttribute(){},remove(){this.removed=true;}};}
 f.document.createElement=()=>{const node=element();nodes.push(node);return node;};
 f.document.body=element();
 f.handlers['style.load']();
 f.run("map.project = point => ({x:200+(point[0]-24)*100000,y:400}); iconCache.set('ccs-sos',{}); for(let i=0;i<=16;i++) iconCache.set('ccs-police-'+i,{});");
 function show(kind,offset){
  f.window.ccsSetFeatures({type:'FeatureCollection',features:[{properties:{kind:'self'},geometry:{type:'Point',coordinates:[24,57]}},{properties:{kind,id:'report',label:kind},geometry:{type:'Point',coordinates:[24+offset,57]}}]});
  f.window.ccsFollow(); f.run('updateEdgeBeacons()');
  return nodes.filter(n=>n.className==='ccs-beacon').at(-1);
 }
 const sos=show('sos',0.0495); // approximately 3km, beyond ordinary beacon range
 assert.equal(sos.dataset.icon,'ccs-sos');
 assert.ok(Number(sos.style.opacity)>0 && Number(sos.style.opacity)<1);
 sos.click({stopPropagation(){}});
 assert.deepEqual(f.messages.at(-1),{type:'select',kind:'sos',id:'report'});
 const police=show('police',-0.0165); // approximately 1km
 assert.match(police.dataset.icon,/^ccs-police-/);
 assert.ok(Number(police.style.opacity)>0 && Number(police.style.opacity)<1);
 const before=police.dataset.icon;
 f.setTime(3000);f.timers.forEach(fn=>fn());f.run('updateEdgeBeacons()');
 assert.notEqual(police.dataset.icon,before);
 police.click({stopPropagation(){}});
 assert.deepEqual(f.messages.at(-1),{type:'select',kind:'police',id:'report'});
 f.handlers.dragstart();
 assert.equal(police.style.opacity,'0');
});

test('speed zoom eases gradually and stationary heading noise cannot rotate follow',()=>{
 const f=fixture();f.handlers['style.load']();
 const packet=(speed,heading)=>({position:[24,57],zoom:16.35,following:true,followRevision:1,speed,heading});
 f.window.ccsSetMotion(packet(0,45));f.tick(0);
 const stationary=f.moves.at(-1).bearing;
 for(let i=1;i<10;i++){f.setTime(i*100);f.window.ccsSetMotion(packet(0,i*37));f.tick(i*100);assert.equal(f.moves.at(-1).bearing,stationary);}
 f.window.ccsSetMotion(packet(100/3.6,90));f.tick(950);
 assert.ok(f.moves.at(-1).zoom>15.35);
 for(let t=1000;t<=8000;t+=50){f.setTime(t);if(t%100===0)f.window.ccsSetMotion(packet(100/3.6,90));f.tick(t);}
 assert.ok(Math.abs(f.moves.at(-1).zoom-15.35)<.01);
 const fast=f.moves.at(-1).zoom;
 f.window.ccsSetMotion(packet(0,270));f.tick(8050);
 assert.ok(f.moves.at(-1).zoom>fast&&f.moves.at(-1).zoom<16.35);
 const frozen=f.moves.at(-1).bearing;
 f.setTime(8100);f.window.ccsSetMotion(packet(0,180));f.tick(8100);
 assert.equal(f.moves.at(-1).bearing,frozen);
 f.handlers.dragstart();const count=f.moves.length;
 f.setTime(8200);f.window.ccsSetMotion(packet(50,0));f.tick(8200);
 assert.equal(f.moves.length,count);
});

test('people beacons show avatar and literal nickname with silhouette fallback',()=>{
 const f=fixture(),nodes=[];
 function element(){return {style:{setProperty(){}},dataset:{},children:[],appendChild(c){this.children.push(c);this.firstChild=this.children[0];this.lastChild=c;},addEventListener(n,fn){this[n]=fn;},getBoundingClientRect(){},getContext(){return {putImageData(){}};},setAttribute(){},remove(){}};}
 f.document.createElement=()=>{const n=element();nodes.push(n);return n;};f.document.body=element();f.handlers['style.load']();
 f.run("map.project = p=>({x:200+(p[0]-24)*100000,y:400});iconCache.set('ccs-person',{});iconCache.set('ccs-avatar-1',{});");
 const live={properties:{kind:'live',id:'u',label:'<b>Nickname</b>',avatarIcon:'ccs-avatar-1'},geometry:{type:'Point',coordinates:[24.01,57]}};
 const data=()=>({type:'FeatureCollection',features:[{properties:{kind:'self'},geometry:{type:'Point',coordinates:[24,57]}},live]});
 f.window.ccsSetFeatures(data());f.window.ccsFollow();f.run('updateEdgeBeacons()');
 const node=nodes.find(n=>n.className==='ccs-beacon ccs-person-beacon');
 assert.equal(node.nickname.textContent,'<b>Nickname</b>');assert.equal(node.dataset.icon,'ccs-avatar-1');
 delete live.properties.avatarIcon;f.window.ccsSetFeatures(data());f.run('updateEdgeBeacons()');assert.equal(node.dataset.icon,'ccs-person');
 node.click({stopPropagation(){}});assert.deepEqual(f.messages.at(-1),{type:'select',kind:'live',id:'u'});
});

test('zoom cannot rotate directional markers; real map rotation compensates both layers',()=>{
 const f=fixture();f.handlers['style.load']();
 for(const id of ['ccs-self','ccs-live-cars']) {
  const layer=f.layers.find(l=>l.id===id);
  assert.equal(layer.layout['icon-rotation-alignment'],'viewport');
  assert.equal(layer.layout['icon-pitch-alignment'],'viewport');
  assert.equal(JSON.stringify(layer.layout['icon-rotate']),JSON.stringify(['-',['coalesce',['get','heading'],0],0]));
 }
 const updates=()=>f.layouts.filter(v=>v[1]==='icon-rotate');
 const count=updates().length;
 for(const zoom of [16,12,8,5,2,5,8,12,16]) {
  f.run(`map.zoom=${zoom};syncMarkerBearing()`);
 }
 assert.equal(updates().length,count);
 f.run('map.bearing=90');f.handlers.rotate();
 assert.equal(updates().length,count+2);
 for(const change of updates().slice(-2)) assert.equal(change[2][2],90);
 // A 90-degree course viewed with a 90-degree map bearing points screen-up.
 assert.equal(90-updates().at(-1)[2][2],0);
 f.window.ccsSetStyle('positron');f.handlers['style.load']();
 assert.equal(f.layers.find(l=>l.id==='ccs-self').layout['icon-rotate'][2],90);
 f.run('map.bearing=-179');f.handlers.rotate();
 assert.equal(updates().at(-1)[2][2],-179);
 assert.equal(f.moves.length,0); // Updating icon orientation never moves the camera.
});

test('moving users and camera metadata do not rebuild static spots',()=>{
 const f=fixture();f.handlers['style.load']();
 const spot={properties:{kind:'spot',id:'a'},geometry:{coordinates:[24,57]}};
 const car=x=>({properties:{kind:'live',id:'u'},geometry:{coordinates:[x,57]}});
 f.window.ccsSetPatch({fixed:[spot],moving:[car(24)],meta:{}});
 const fixed=f.sources.ccs.data, live=f.sources['ccs-live'].data;
 f.window.ccsSetPatch({moving:[car(25)],meta:{selection:{id:'a'}}});
 assert.equal(f.sources.ccs.data,fixed);
 assert.notEqual(f.sources['ccs-live'].data,live);
 f.window.ccsSetPatch({fixed:[],moving:[],meta:{}});
 assert.equal(f.sources.ccs.data.features.length,0);
 assert.equal(f.sources['ccs-live'].data.features.length,0);
});
test('stationary motion settles and repeated unchanged fixes do not move camera',()=>{
 const f=fixture();f.handlers['style.load']();
 const packet={position:[24,57],heading:0,speed:0,following:true,zoom:16};
 f.window.ccsSetMotion(packet);f.tick(16);
 assert.equal(f.frames.size,0);
 const moves=f.moves.length;
 f.setTime(1000);f.window.ccsSetMotion(packet);f.tick(1016);
 assert.equal(f.moves.length,moves);assert.equal(f.frames.size,0);
});
test('alerts outside the viewport and beacon range do not animate',()=>{
 const f=fixture();f.handlers['style.load']();
 f.run('map.project=()=>({x:-5000,y:-5000})');
 f.window.ccsSetFeatures({features:[{properties:{kind:'police'},geometry:{coordinates:[0,0]}}]});
 assert.equal(f.timers.size,0);
 f.run('map.project=()=>({x:200,y:200})');f.handlers.render();
 assert.equal(f.timers.size,1);
});
test('frame budget follows gestures, explicit follow and visibility',()=>{
 const f=fixture(), budgets=[];f.window.ccsFrameBudget=(follow,visible)=>budgets.push([follow,visible]);f.handlers['style.load']();
 f.window.ccsSetMotion({position:[24,57],heading:0,speed:0,following:true,zoom:16});
 assert.deepEqual(budgets.at(-1),[true,true]);
 f.touches.touchstart({touches:[{}]});assert.deepEqual(budgets.at(-1),[false,true]);
 f.handlers.dragstart();f.touches.touchend({touches:[]});assert.deepEqual(budgets.at(-1),[false,true]);
 f.window.ccsSetActive(false);assert.deepEqual(budgets.at(-1),[false,false]);
});
test('spot beacons use original inner artwork in both themes and retain selection',()=>{
 const f=fixture(),nodes=[];
 function element(){return {style:{setProperty(){}},dataset:{},children:[],appendChild(c){this.children.push(c);this.lastChild=c;},addEventListener(n,fn){this[n]=fn;},getBoundingClientRect(){},getContext(){return {putImageData(){}}},setAttribute(){},remove(){}};}
 f.document.createElement=()=>{const e=element();nodes.push(e);return e;};f.document.body=element();f.handlers['style.load']();
 f.run("map.project=p=>({x:200+(p[0]-24)*100000,y:400}); iconCache.set('assets/spot_icons/wash.png@beacon-dark',{});iconCache.set('assets/spot_icons/wash.png@beacon-light',{});");
 f.window.ccsSetFeatures({features:[{properties:{kind:'self'},geometry:{type:'Point',coordinates:[24,57]}},{properties:{kind:'spot',id:'wash',icon:'assets/spot_icons/wash.png',color:'#0088ff'},geometry:{type:'Point',coordinates:[24.012,57]}}]});
 f.window.ccsFollow();f.run('updateEdgeBeacons()');const beacon=nodes.find(n=>n.className==='ccs-beacon'),layer=nodes.find(n=>n.id==='ccs-beacons');
 assert.equal(beacon.dataset.icon,'assets/spot_icons/wash.png@beacon-dark');assert.equal(layer.dataset.theme,'dark');
 f.window.ccsSetStyle('positron');f.handlers['style.load']();f.run('updateEdgeBeacons()');
 assert.equal(beacon.dataset.icon,'assets/spot_icons/wash.png@beacon-light');assert.equal(layer.dataset.theme,'light');
 beacon.click({stopPropagation(){}});assert.deepEqual(f.messages.at(-1),{type:'select',kind:'spot',id:'wash'});
});
