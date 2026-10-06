/* Map code and user data stay inside this view. Only basemap requests leave it. */
'use strict';
const statusBox = document.getElementById('status');
const notify = (type, extra = {}) => window.CcsGlobe?.postMessage(JSON.stringify({type, ...extra}));
let map, latest = {type:'FeatureCollection',features:[]}, ready = false, following = false, currentStyle='dark';
let cameraRevision;
let attributionPresented=false;
function collapseInitialAttribution() {
  if(attributionPresented) return;
  const control=document.querySelector?.('.maplibregl-ctrl-attrib');
  if(!control) return;
  attributionPresented=true;
  // OSM permits automatic collapse after five seconds; credits remain accessible.
  const timeout=setTimeout(()=>control.classList.remove('maplibregl-compact-show'),5000);
  control.querySelector('summary')?.addEventListener('click',()=>clearTimeout(timeout),{once:true});
}
const iconCache = new Map();
// Reuse the bundled CCS category PNGs; never fetch icons.
window.ccsSetIcons = icons => {
  for (const [id, uri] of Object.entries(icons)) {
    if ((!id.startsWith('assets/spot_icons/') && !/^assets\/user_cars\/car_(green|blue|purple)\.png$/.test(id) && !/^ccs-(self-arrow|pin-(blue|amber|red)|police-([0-9]|1[0-6])|sos)$/.test(id)) || !uri.startsWith('data:image/png;base64,')) continue;
    const image = new Image();
    image.onload = () => {
      for (const tint of (!id.startsWith('assets/spot_icons/') ? [''] : ['', '#616161', '#ffab40'])) {
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
    image.onerror = () => {statusBox.textContent='Some spot icons could not load. Retry the map.';statusBox.hidden=false;};
    image.src=uri;
  }
};
// Small motion packets use their own source; hundreds of spots are not rebuilt
// at animation-frame frequency. Both arrow and camera use the same interpolation.
let motionReceived=false, motionPosition=null, motionHeading=0, motionFollowing=false;
let motionFrame=null;
let gestureBlocked=false, followRevision=0;
let manualTouchActive=false;
let motionTarget=null, motionAt=0, motionLastFrame=null, motionVelocity=[0,0];
function motionData() {return {type:'FeatureCollection',features:motionPosition?[{
  type:'Feature',geometry:{type:'Point',coordinates:motionPosition},properties:{kind:'self',heading:motionHeading}
}]:[]};}
function stopMotion() {if(motionFrame!==null) cancelAnimationFrame(motionFrame); motionFrame=null;motionLastFrame=null;}
const shortArc = value => ((value+540)%360)-180;
function animateMotion(now) {
  motionFrame=null;
  if(!ready || !viewActive || !motionTarget) {motionLastFrame=null;return;}
  const dt=motionLastFrame===null?1/60:Math.min(.05,Math.max(0,(now-motionLastFrame)/1000));
  motionLastFrame=now;
  const age=Math.max(0,(now-motionAt)/1000);
  // Bridge jitter is predicted for only 150 ms; native GPS prediction handles
  // longer gaps. One continuous frame loop avoids restarting animations at 10 Hz.
  const ahead=Math.min(.15,age);
  const target=[motionTarget.position[0]+motionVelocity[0]*ahead,motionTarget.position[1]+motionVelocity[1]*ahead];
  const blend=1-Math.exp(-dt/.065);
  motionPosition=[motionPosition[0]+shortArc(target[0]-motionPosition[0])*blend,motionPosition[1]+(target[1]-motionPosition[1])*blend];
  motionHeading+=shortArc(motionTarget.heading-motionHeading)*(1-Math.exp(-dt/.12));
  map.getSource('ccs-motion')?.setData(motionData());
  if(motionFollowing) map.jumpTo({center:motionPosition,zoom:motionTarget.zoom,bearing:motionHeading});
  if(age<1) motionFrame=requestAnimationFrame(animateMotion);
  else motionLastFrame=null;
}
window.ccsSetMotion = data => {
  motionReceived=true;
  if(data.followRevision!==undefined && data.followRevision!==followRevision) {
    followRevision=data.followRevision;gestureBlocked=false;
  }
  motionFollowing=!!data.following && !gestureBlocked;
  if(!data.position) {stopMotion();motionTarget=null;motionPosition=null;motionVelocity=[0,0];if(ready) map.getSource('ccs-motion')?.setData(motionData());return;}
  const now=performance.now(), seconds=(now-motionAt)/1000;
  motionVelocity=[0,0];
  if(motionTarget && seconds>=.04 && seconds<=.5) {
    const velocity=[shortArc(data.position[0]-motionTarget.position[0])/seconds,(data.position[1]-motionTarget.position[1])/seconds];
    const metersPerSecond=Math.hypot(velocity[0]*Math.cos(data.position[1]*Math.PI/180),velocity[1])*111320;
    if(metersPerSecond<=70) motionVelocity=velocity;
  }
  if(!motionPosition || seconds>3) {motionPosition=data.position.slice();motionHeading=data.heading;}
  motionTarget=data;motionAt=now;
  if(motionFrame===null) motionFrame=requestAnimationFrame(animateMotion);
};
function currentPosition() { return latest.features.find(f => f.properties.kind === 'self')?.geometry.coordinates; }
function follow() {
  const p = currentPosition();
  if (p) map.easeTo({center:p, zoom:Math.max(map.getZoom(),15),duration:900});
}
window.ccsSetFeatures = data => {
  latest = data;
  if(!motionReceived) {
    const self=data.features.find(f=>f.properties.kind==='self');
    motionPosition=self?.geometry.coordinates||null; motionHeading=self?.properties.heading||0;
    if(ready) map.getSource('ccs-motion')?.setData(motionData());
  }
  startAlertAnimation();
  if (ready) {
    map.getSource('ccs').setData(data);
    const camera=data.camera;
    if(camera && camera.revision !== cameraRevision) {
      cameraRevision=camera.revision; following=false;
      if(camera.bounds) {
        const [a,b]=camera.bounds;
        const east=a[0]+shortArc(b[0]-a[0]);
        const bounds=[[Math.min(a[0],east),Math.min(a[1],b[1])],[Math.max(a[0],east),Math.max(a[1],b[1])]];
        motionFollowing=false;following=false;gestureBlocked=true;
        map.fitBounds(bounds,{padding:{top:100,bottom:160,left:45,right:45},bearing:0,pitch:0,maxZoom:15.6,duration:500});
      }
      else if(!motionFollowing && !manualTouchActive) map.easeTo({center:camera.center,zoom:camera.zoom,...(!gestureBlocked?{bearing:camera.bearing||0}:{}),duration:250});
    } else if(following) follow();
  }
};
window.ccsFollow = () => { gestureBlocked=false; following = true; follow(); };
window.ccsWorld = () => { gestureBlocked=true; following = false; motionFollowing=false; notify('gesture'); map.easeTo({zoom:1.3,pitch:0,duration:1200}); };
window.ccsSetStyle = style => {
  if (!['dark','positron'].includes(style) || style===currentStyle) {notify('ready');return;}
  stopAlertAnimation(); currentStyle=style; ready=false;
  map.setStyle('https://tiles.openfreemap.org/styles/'+style);
};
let alertTimer=null, viewActive=true;
function stopAlertAnimation() { if(alertTimer!==null) clearInterval(alertTimer); alertTimer=null; }
window.ccsSetActive = active => {viewActive=!!active; if(viewActive) startAlertAnimation(); else {stopAlertAnimation();stopMotion();}};
function alertRadius(kind) {
  const stops=['interpolate',['linear'],['zoom']];
  for(const z of [1,4,5,7,9,11,12,14.19,14.2,15,16,17,18]) {
    let size;
    if(z>=14.2) {const p=Math.max(0,Math.min(1,(z-14.2)/2.8));size=(kind==='police'?42:46)+(kind==='police'?32:36)*(1-Math.pow(1-p,3));}
    else if(kind==='police') size=3+19*Math.pow(Math.max(0,(z-5)/9.2),2.4);
    else {const p=Math.max(0,Math.min(1,(z-4)/10.2));size=15+11*(1-Math.pow(1-p,3));}
    stops.push(z,size/2);
  }
  return stops;
}
function addAlertLayers() {
  for(const kind of ['police','sos']) {
    const filter=['==',['get','kind'],kind], color=kind==='police'?'#1565ff':'#ff2d55';
    const opacity=kind==='police'?['interpolate',['linear'],['zoom'],5,0,12,1]:1;
    map.addLayer({id:'ccs-'+kind+'-glow',type:'circle',source:'ccs',filter,paint:{'circle-radius':alertRadius(kind),'circle-color':color,'circle-blur':0.8,'circle-opacity':kind==='police'?['interpolate',['linear'],['zoom'],5,0,12,0.32]:0.34}});
    map.addLayer({id:'ccs-'+kind+'-core',type:'circle',source:'ccs',filter,paint:{
      'circle-radius':alertRadius(kind),'circle-color':color,
      'circle-opacity':kind==='police'?['interpolate',['linear'],['zoom'],5,0,12,0.9,14.19,0.9,14.2,0.14]:['step',['zoom'],0.9,14.2,0.24],
      'circle-stroke-color':color,'circle-stroke-width':2,'circle-stroke-opacity':opacity}});
    map.addLayer({id:'ccs-'+kind+'-badge',type:'symbol',source:'ccs',filter,minzoom:14.2,layout:{
      'icon-image':kind==='police'?'ccs-police-0':'ccs-sos','icon-size':(kind==='police'?34:38)/64,
      'icon-allow-overlap':true,'icon-ignore-placement':true,'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport'}});
  }
}
function animateAlerts() {
  if(!ready || !viewActive) return;
  const t=(Date.now()%6000)/3000, p=(1-Math.cos(Math.PI*(t<=1?t:2-t)))/2;
  const rgb=[21+(255-21)*p,101+(45-101)*p,255+(85-255)*p].map(Math.round);
  const color='rgb('+rgb.join(',')+')';
  for(const layer of ['ccs-police-core','ccs-police-glow']) map.setPaintProperty(layer,'circle-color',color);
  map.setPaintProperty('ccs-police-core','circle-stroke-color',color);
  map.setLayoutProperty('ccs-police-badge','icon-image','ccs-police-'+Math.round(p*16));
  map.setPaintProperty('ccs-sos-glow','circle-opacity',0.34+p*0.22);
  map.setPaintProperty('ccs-sos-core','circle-opacity',['step',['zoom'],0.82+p*0.14,14.2,0.18+p*0.12]);
  map.setPaintProperty('ccs-sos-core','circle-stroke-opacity',0.82+p*0.18);
}
function startAlertAnimation() {
  stopAlertAnimation();
  if(!ready || !viewActive || !latest.features.some(f=>['police','sos'].includes(f.properties.kind))) return;
  animateAlerts(); alertTimer=setInterval(animateAlerts,80);
}
try {
  map = new maplibregl.Map({container:'map',style:'https://tiles.openfreemap.org/styles/dark',center:[24.1,56.95],zoom:6.5,maxZoom:18,attributionControl:{compact:true}});
  // Native compact controls own globe/follow; pinch gestures provide zoom.
  const browse = () => {gestureBlocked=true;following=false;motionFollowing=false;notify('gesture');};
  // Capture the second finger before MapLibre handles the pinch. Camera jumpTo
  // updates can otherwise interrupt zoomstart before it carries originalEvent.
  const surface=document.getElementById('map');
  const touch = e => {
    manualTouchActive=e.touches.length>0;
    if(e.touches.length>=2 && !gestureBlocked) {browse();map.stop?.();}
  };
  for(const type of ['touchstart','touchmove','touchend','touchcancel']) {
    surface.addEventListener?.(type,touch,{capture:true,passive:true});
  }
  map.on('dragstart', browse);
  map.on('zoomstart', e => {if(e.originalEvent) browse();});
  map.on('rotatestart', e => {if(e.originalEvent) browse();});
  map.on('pitchstart', e => {if(e.originalEvent) browse();});
  map.on('moveend', () => {if(motionFollowing) return; const p=map.getCenter(); notify('camera',{lat:p.lat,lng:p.lng,zoom:map.getZoom()});});
  map.on('error', () => {notify('error');statusBox.textContent='Map could not load. Check your connection or retry the map.';statusBox.hidden=false;});
  map.on('style.load', () => {
    map.setProjection({type:'globe'});
    for (const [key,pixels] of iconCache) map.addImage(key,pixels,{pixelRatio:2});
    map.addSource('ccs',{type:'geojson',data:latest});
    map.addSource('ccs-motion',{type:'geojson',data:motionData()});
    map.addLayer({id:'ccs-restricted',type:'fill',source:'ccs',filter:['==',['get','kind'],'restricted'],paint:{'fill-color':'#ff5252','fill-opacity':0.16}});
    map.addLayer({id:'ccs-pin',type:'symbol',source:'ccs',filter:['==',['get','kind'],'pin'],layout:{
      'icon-image':['coalesce',['get','icon'],'ccs-pin-blue'],'icon-size':56/64,'icon-anchor':'bottom',
      'icon-allow-overlap':true,'icon-ignore-placement':true,'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport'}});
    map.addLayer({id:'ccs-route',type:'line',source:'ccs',filter:['==',['get','kind'],'route'],paint:{'line-color':'#008dff','line-width':3,'line-dasharray':[2,2]}});
    const spots=['==',['get','kind'],'spot'];
    const dotSize=['interpolate',['linear'],['zoom']];
    for(const z of [1,3,5,7,9,10,11.25,18]) {
      const p=Math.max(0,Math.min(1,(z-3)/(11.25-3)));
      dotSize.push(z,['*',(3.2+7.2*Math.pow(p,2.7))/2,['case',['get','event'],1.04,1]]);
    }
    // A small, soft halo keeps distant spots legible without enlarging the dot.
    // Fade with zoom; muted/visited markers keep their subdued appearance.
    map.addLayer({id:'ccs-spot-glow',type:'circle',source:'ccs',filter:spots,paint:{
      'circle-radius':['interpolate',['linear'],['zoom'],1,4,7,5,10,7,11.25,9,13,12,16,14,18,14],
      'circle-color':['coalesce',['get','color'],'#4d90ff'],
      'circle-blur':0.85,
      'circle-opacity':['interpolate',['linear'],['zoom'],
        1,['case',['get','tint'],0.12,0.30],
        9,['case',['get','tint'],0.09,0.23],
        11.25,['case',['get','tint'],0.065,0.16],
        14,['case',['get','tint'],0.025,0.065],
        18,0.015]}});
    map.addLayer({id:'ccs-points',type:'circle',source:'ccs',filter:spots,maxzoom:11.25,paint:{
      'circle-radius':dotSize,
      'circle-color':['coalesce',['get','color'],'#4d90ff'],
      'circle-opacity':['case',['get','tint'],0.58,1],
      'circle-stroke-opacity':0.8,
      'circle-stroke-color':['case',['get','event'],'#ffab40','#ffffff'],
      'circle-stroke-width':['interpolate',['linear'],['zoom'],3,0.35,11.25,0.65]}});
    const iconSize=['interpolate',['linear'],['zoom']];
    for(const z of [11.25,12,13,14,15,16,18]) {
      const p=Math.max(0,Math.min(1,(z-11.25)/(16-11.25)));
      iconSize.push(z,['*',(38+27*(1-Math.pow(1-p,3)))/64,['case',['get','event'],1.16,1]]);
    }
    const spotIcon=['get',currentStyle==='positron'?'lightIcon':'icon'];
    map.addLayer({id:'ccs-spot-icons',type:'symbol',source:'ccs',filter:spots,minzoom:11.25,layout:{
      'icon-image':['case',['get','tint'],['concat',spotIcon,'@',['get','color']],spotIcon],
      'icon-size':iconSize,'icon-allow-overlap':true,'icon-ignore-placement':true,
      'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport'},
      paint:{'icon-opacity':['coalesce',['get','opacity'],1]}});
    const carSize=['interpolate',['linear'],['zoom']];
    for(const z of [1,4,7,10,13,15,17,18]) {
      const p=Math.max(0,Math.min(1,(z-4)/13));
      carSize.push(z,(9+25*(1-Math.pow(1-p,3)))/64);
    }
    map.addLayer({id:'ccs-live-cars',type:'symbol',source:'ccs',filter:['==',['get','kind'],'live'],layout:{
      'icon-image':['coalesce',['get','icon'],'assets/user_cars/car_green.png'],'icon-size':carSize,
      'icon-rotate':['coalesce',['get','heading'],0],'icon-rotation-alignment':'map',
      'icon-pitch-alignment':'viewport','icon-allow-overlap':true,'icon-ignore-placement':true}});
    map.addLayer({id:'ccs-self',type:'symbol',source:'ccs-motion',filter:['==',['get','kind'],'self'],layout:{
      'icon-image':'ccs-self-arrow','icon-size':['interpolate',['linear'],['zoom'],3,18/64,16,62/64],
      'icon-rotate':['coalesce',['get','heading'],0], 'icon-rotation-alignment':'map',
      'icon-pitch-alignment':'viewport','icon-allow-overlap':true,'icon-ignore-placement':true}});
    addAlertLayers();
    const labelFont=map.getStyle().layers.find(l=>l.layout?.['text-font'])?.layout['text-font'] || ['Noto Sans Regular'];
    map.addLayer({id:'ccs-labels',type:'symbol',source:'ccs',filter:['all',['==',['geometry-type'],'Point'],['!=',['get','kind'],'self']],minzoom:12.35,layout:{
      'text-font':labelFont,'text-field':['get','label'],
      'text-size':['interpolate',['linear'],['zoom'],11.25,8.2,16,10],
      'text-anchor':'bottom','text-offset':[0,-4]},
      paint:{'text-color':currentStyle==='positron'?'#182333':'#ffffff','text-halo-color':currentStyle==='positron'?'#ffffff':'#101827','text-halo-width':2,
        'text-opacity':['interpolate',['linear'],['zoom'],12.35,0,14.25,1]}});
    ready=true; statusBox.hidden=true; notify('ready'); startAlertAnimation(); collapseInitialAttribution();
  });
  map.on('click', e => {
    if(!ready) return;
    if(e.lngLat) notify('pick',{lat:e.lngLat.lat,lng:e.lngLat.lng});
    const p=map.queryRenderedFeatures(e.point,{layers:['ccs-spot-icons','ccs-points','ccs-live-cars','ccs-police-core','ccs-sos-core','ccs-police-badge','ccs-sos-badge']})[0]?.properties;
    if(p && p.kind!=='self') notify('select',{kind:p.kind,id:p.id});
    else if(!p) notify('clear');
  });
} catch (_) {statusBox.textContent='This device could not start the globe. Please retry.';notify('error');}
