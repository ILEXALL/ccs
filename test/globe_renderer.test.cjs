const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function fixture() {
  const handlers={}, messages=[], moves=[], sources={}, layers=[];
  class Map {
    constructor() {this.zoom=1;}
    addControl() {}
    on(name,...args) {handlers[name+(args.length===2?':'+args[0]:'')]=args.at(-1);}
    setStyle(url) {this.style=url;layers.length=0;delete sources.ccs;}
    setProjection(p) {this.projection=p;}
    setPaintProperty() {}
    getStyle() {return {layers:[]};}
    addSource(id,source) {sources[id]={...source,setData(d){this.data=d;}};}
    getSource(id) {return sources[id];}
    addLayer(layer) {layers.push(layer);}
    queryRenderedFeatures(point) {return point;}
    getZoom() {return this.zoom;}
    easeTo(move) {moves.push(move);}
  }
  const context={window:{CcsGlobe:{postMessage:m=>messages.push(JSON.parse(m))}},document:{getElementById:()=>({})},maplibregl:{Map,NavigationControl:class{}}};
  vm.runInNewContext(fs.readFileSync('assets/globe/globe.js','utf8'),context);
  return {...context,handlers,messages,moves,sources,layers};
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
