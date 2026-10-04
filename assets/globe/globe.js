/* Map code and user data stay inside this view. Only basemap requests leave it. */
'use strict';
const statusBox = document.getElementById('status');
const notify = (type, extra = {}) => window.CcsGlobe?.postMessage(JSON.stringify({type, ...extra}));
let map, latest = {type:'FeatureCollection',features:[]}, ready = false, following = false, currentStyle='dark';
const iconCache = new Map();
// Reuse the exact bundled category PNGs from the standard map; never fetch icons.
window.ccsSetIcons = icons => {
  for (const [id, uri] of Object.entries(icons)) {
    if ((!id.startsWith('assets/spot_icons/') && id!=='ccs-self-arrow') || !uri.startsWith('data:image/png;base64,')) continue;
    const image = new Image();
    image.onload = () => {
      for (const tint of ['', '#616161', '#ffab40']) {
        const canvas = document.createElement('canvas'); canvas.width=128; canvas.height=128;
        const ctx = canvas.getContext('2d');
        const scale = Math.min(128/image.width,128/image.height);
        const w=image.width*scale,h=image.height*scale;
        ctx.drawImage(image,(128-w)/2,(128-h)/2,w,h);
        if(tint) {ctx.globalCompositeOperation='source-atop';ctx.fillStyle=tint;ctx.fillRect(0,0,128,128);}
        const key=id+(tint?'@'+tint:'');
        const pixels=ctx.getImageData(0,0,128,128);
        iconCache.set(key,pixels);
        if(ready && !map.hasImage(key)) map.addImage(key,pixels,{pixelRatio:2});
      }
    };
    image.onerror = () => {statusBox.textContent='Some spot icons could not load. Reopen the preview.';statusBox.hidden=false;};
    image.src=uri;
  }
};
function currentPosition() { return latest.features.find(f => f.properties.kind === 'self')?.geometry.coordinates; }
function follow() {
  const p = currentPosition();
  if (p) map.easeTo({center:p, zoom:Math.max(map.getZoom(),15),duration:900});
}
window.ccsSetFeatures = data => {
  latest = data;
  if (ready) { map.getSource('ccs').setData(data); if(following) follow(); }
};
window.ccsFollow = () => { following = true; follow(); };
window.ccsWorld = () => { following = false; map.easeTo({zoom:1.3,pitch:0,duration:1200}); };
window.ccsSetStyle = style => {
  if (!['dark','positron'].includes(style) || style===currentStyle) {notify('ready');return;}
  currentStyle=style; ready=false;
  map.setStyle('https://tiles.openfreemap.org/styles/'+style);
};
try {
  map = new maplibregl.Map({container:'map',style:'https://tiles.openfreemap.org/styles/dark',center:[24,45],zoom:1.3,maxZoom:18,attributionControl:{compact:false}});
  // Native compact controls own globe/follow; pinch gestures provide zoom.
  map.on('dragstart', () => {following=false;});
  map.on('error', () => {statusBox.textContent='Map could not load. Check your connection or reopen the preview.';statusBox.hidden=false;});
  map.on('style.load', () => {
    map.setProjection({type:'globe'});
    for (const [key,pixels] of iconCache) map.addImage(key,pixels,{pixelRatio:2});
    map.addSource('ccs',{type:'geojson',data:latest});
    const spots=['==',['get','kind'],'spot'];
    const dotSize=['interpolate',['linear'],['zoom']];
    for(const z of [1,3,5,7,9,10,11.25,18]) {
      const p=Math.max(0,Math.min(1,(z-3)/(11.25-3)));
      dotSize.push(z,['*',(4+9*Math.pow(p,2.7))/2,['case',['get','event'],1.04,1]]);
    }
    map.addLayer({id:'ccs-points',type:'circle',source:'ccs',filter:spots,maxzoom:11.25,paint:{
      'circle-radius':dotSize,
      'circle-color':['coalesce',['get','color'],'#4d90ff'],
      'circle-opacity':['case',['get','tint'],0.58,1],
      'circle-stroke-opacity':0.8,
      'circle-stroke-color':['case',['get','event'],'#ffab40','#ffffff'],
      'circle-stroke-width':['interpolate',['linear'],['zoom'],3,0.45,11.25,0.85]}});
    const iconSize=['interpolate',['linear'],['zoom']];
    for(const z of [11.25,12,13,14,15,16,18]) {
      const p=Math.max(0,Math.min(1,(z-11.25)/(16-11.25)));
      iconSize.push(z,['*',(46+24*(1-Math.pow(1-p,3)))/64,['case',['get','event'],1.16,1]]);
    }
    const spotIcon=['get',currentStyle==='positron'?'lightIcon':'icon'];
    map.addLayer({id:'ccs-spot-icons',type:'symbol',source:'ccs',filter:spots,minzoom:11.25,layout:{
      'icon-image':['case',['get','tint'],['concat',spotIcon,'@',['get','color']],spotIcon],
      'icon-size':iconSize,'icon-allow-overlap':true,'icon-ignore-placement':true,
      'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport'},
      paint:{'icon-opacity':['coalesce',['get','opacity'],1]}});
    map.addLayer({id:'ccs-live-points',type:'circle',source:'ccs',filter:['==',['get','kind'],'live'],paint:{
      'circle-radius':['interpolate',['linear'],['zoom'],1,3,12,8,17,11],
      'circle-color':['match',['get','kind'],'spot','#4d90ff','self','#ffffff','#38dfba'],
      'circle-stroke-color':'#0b1323','circle-stroke-width':2}});
    map.addLayer({id:'ccs-self',type:'symbol',source:'ccs',filter:['==',['get','kind'],'self'],layout:{
      'icon-image':'ccs-self-arrow','icon-size':['interpolate',['linear'],['zoom'],3,18/64,16,62/64],
      'icon-rotate':['coalesce',['get','heading'],0], 'icon-rotation-alignment':'map',
      'icon-pitch-alignment':'viewport','icon-allow-overlap':true,'icon-ignore-placement':true}});
    map.addLayer({id:'ccs-alerts',type:'circle',source:'ccs',filter:['in',['get','kind'],['literal',['police','sos']]],paint:{
      'circle-radius':14,'circle-color':['match',['get','kind'],'police','#287cff','#ef3340'],
      'circle-stroke-color':'#ffffff','circle-stroke-width':2}});
    const labelFont=map.getStyle().layers.find(l=>l.layout?.['text-font'])?.layout['text-font'] || ['Noto Sans Regular'];
    map.addLayer({id:'ccs-labels',type:'symbol',source:'ccs',minzoom:12.35,layout:{
      'text-font':labelFont,'text-field':['get','label'],
      'text-size':['interpolate',['linear'],['zoom'],11.25,8.2,16,10],
      'text-anchor':'bottom','text-offset':[0,-4]},
      paint:{'text-color':currentStyle==='positron'?'#182333':'#ffffff','text-halo-color':currentStyle==='positron'?'#ffffff':'#101827','text-halo-width':2,
        'text-opacity':['interpolate',['linear'],['zoom'],12.35,0,14.25,1]}});
    ready=true; statusBox.hidden=true; notify('ready');
  });
  map.on('click', e => {
    if(!ready) return;
    const p=map.queryRenderedFeatures(e.point,{layers:['ccs-spot-icons','ccs-points','ccs-live-points','ccs-alerts']})[0]?.properties;
    if(p && p.kind!=='self') notify('select',{kind:p.kind,id:p.id});
    else if(!p) notify('clear');
  });
} catch (_) {statusBox.textContent='This device could not start the globe. Use the standard map.';notify('error');}
