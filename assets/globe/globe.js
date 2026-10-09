/* Map code and user data stay inside this view. Only basemap requests leave it. */
'use strict';
const statusBox = document.getElementById('status');
const notify = (type, extra = {}) => window.CcsGlobe?.postMessage(JSON.stringify({type, ...extra}));
let map, latest = {type:'FeatureCollection',features:[]}, ready = false, following = false, currentStyle='dark';
let cameraRevision;
let patchFixed=[], patchMoving=[];
window.ccsSetPatch = patch => {
  if(patch.fixed) patchFixed=patch.fixed;
  if(patch.moving) patchMoving=patch.moving;
  window.ccsSetFeatures({...patch.meta,type:'FeatureCollection',features:[...patchFixed,...patchMoving]});
};
let staticData={type:'FeatureCollection',features:[]}, liveData={type:'FeatureCollection',features:[]};
let staticSignature=null, liveSignature=null;
let notifiedFollow=null;
function syncFrameBudget() {
  const enabled=(motionFollowing || following) && !gestureBlocked;
  window.ccsFrameBudget?.(enabled && !manualTouchActive, viewActive);
  if(notifiedFollow!==enabled) {notifiedFollow=enabled;notify('follow',{enabled});}
}

let policeBeaconFrame = 0;
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
// Extract the original neutral-colour illustration inside the coloured pin.
// This runs once per loaded asset, not during navigation or beacon animation.
function cacheBeaconArtwork(id, image) {
  if(!id.startsWith('assets/spot_icons/') || id.includes('_light')) return;
  const source=document.createElement('canvas');source.width=256;source.height=256;
  const context=source.getContext('2d');context.drawImage(image,0,0,256,256);
  const pixels=context.getImageData(0,0,256,256);
  let left=256,top=256,right=0,bottom=0;
  for(let y=0;y<256;y++) for(let x=0;x<256;x++) {
    const i=(y*256+x)*4, r=pixels.data[i],g=pixels.data[i+1],b=pixels.data[i+2];
    // All bundled pins place the artwork in this upper interior region.
    const ink=x>=51 && x<205 && y>=31 && y<166 && Math.min(r,g,b)>110 && Math.max(r,g,b)-Math.min(r,g,b)<65;
    if(!ink) {pixels.data[i+3]=0;continue;}
    if(pixels.data[i+3]>24) {left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}
  }
  if(right<=left || bottom<=top) return;
  for(const [theme,color] of [['dark',[255,255,255]],['light',[24,35,51]],['muted',[97,97,97]],['event',[178,99,0]]]) {
    for(let i=0;i<pixels.data.length;i+=4) {pixels.data[i]=color[0];pixels.data[i+1]=color[1];pixels.data[i+2]=color[2];}
    context.putImageData(pixels,0,0);
    const out=document.createElement('canvas');out.width=128;out.height=128;
    const ctx=out.getContext('2d'),w=right-left+1,h=bottom-top+1,scale=100/Math.max(w,h);
    ctx.drawImage(source,left,top,w,h,(128-w*scale)/2,(128-h*scale)/2,w*scale,h*scale);
    iconCache.set(id+'@beacon-'+theme,ctx.getImageData(0,0,128,128));
  }
}

// Reuse the bundled CCS category PNGs; never fetch icons.
window.ccsSetIcons = icons => {
  for (const [id, uri] of Object.entries(icons)) {
    if ((!id.startsWith('assets/spot_icons/') && !/^assets\/user_cars\/car_(green|blue|purple)\.png$/.test(id) && !/^ccs-(self-arrow|pin-(blue|amber|red)|police-([0-9]|1[0-6])|sos|speed-camera|person|avatar-[0-9]+)$/.test(id)) || !uri.startsWith('data:image/png;base64,')) continue;
    const image = new Image();
    image.onload = () => {
      cacheBeaconArtwork(id,image);
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
let motionFrame=null, followZoom=null, lastMotionSignature=null, lastCameraSignature=null;
let gestureBlocked=false, followRevision=0;
let manualTouchActive=false;
let motionTarget=null, motionAt=0, motionLastFrame=null, motionVelocity=[0,0];
let motionTurnVelocity=0;
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
  // Critically damped steering preserves angular velocity between GPS packets.
  // New headings accelerate/brake the turn instead of instantly changing its rate.
  const headingError=-shortArc(motionTarget.heading-motionHeading);
  const omega=8, decay=Math.exp(-omega*dt);
  const spring=motionTurnVelocity+omega*headingError;
  const turn=headingError*(decay-1)+spring*dt*decay;
  motionTurnVelocity=Math.max(-75,Math.min(75,(motionTurnVelocity-omega*spring*dt)*decay));
  motionHeading+=Math.max(-75*dt,Math.min(75*dt,turn));
  const zoomTarget=speedFollowZoom(motionTarget.zoom, motionTarget.speed);
  followZoom=followZoom===null?motionTarget.zoom:followZoom+(zoomTarget-followZoom)*(1-Math.exp(-dt/1.2));
  if(Math.abs(shortArc(target[0]-motionPosition[0]))<1e-8 && Math.abs(target[1]-motionPosition[1])<1e-8) motionPosition=target.slice();
  if(Math.abs(shortArc(motionTarget.heading-motionHeading))<.02 && Math.abs(motionTurnVelocity)<.1) {motionHeading=motionTarget.heading;motionTurnVelocity=0;}
  if(Math.abs(zoomTarget-followZoom)<.001) followZoom=zoomTarget;
  const signature=JSON.stringify([motionPosition,motionHeading]);
  if(signature!==lastMotionSignature) {map.getSource('ccs-motion')?.setData(motionData());lastMotionSignature=signature;}
  const cameraSignature=JSON.stringify([motionPosition,motionHeading,followZoom,followOffset()]);
  if(motionFollowing && cameraSignature!==lastCameraSignature) {
    map.easeTo({center:motionPosition,zoom:followZoom,bearing:motionHeading,offset:followOffset(),padding:0,duration:0});lastCameraSignature=cameraSignature;
  }
  const unsettled=Math.abs(shortArc(target[0]-motionPosition[0]))>1e-8 || Math.abs(target[1]-motionPosition[1])>1e-8 || Math.abs(shortArc(motionTarget.heading-motionHeading))>.02 || Math.abs(motionTurnVelocity)>.1;
  const predicting=age<.15 && Math.hypot(...motionVelocity)>0;
  const turning=Math.abs(shortArc(motionTarget.heading-motionHeading))>.02 || Math.abs(motionTurnVelocity)>.1;
  if((age<1 && (unsettled || predicting)) || (age<10 && turning) || (motionFollowing && Math.abs(zoomTarget-followZoom)>.001 && age<10)) motionFrame=requestAnimationFrame(animateMotion);
  else motionLastFrame=null;
}
window.ccsSetMotion = data => {
  motionReceived=true;
  if(data.followRevision!==undefined && data.followRevision!==followRevision) {
    followRevision=data.followRevision;gestureBlocked=false;
  }
  const wasFollowing=motionFollowing;
  motionFollowing=!!data.following && !gestureBlocked;
  if(motionFollowing!==wasFollowing) lastCameraSignature=null;
  syncFrameBudget();
  if (!motionFollowing) updateEdgeBeacons();
  if(!data.position) {stopMotion();motionTarget=null;motionPosition=null;motionVelocity=[0,0];motionTurnVelocity=0;if(ready) map.getSource('ccs-motion')?.setData(motionData());return;}
  const now=performance.now(), seconds=(now-motionAt)/1000;
  motionVelocity=[0,0];
  if(motionTarget && seconds>=.04 && seconds<=.5) {
    const velocity=[shortArc(data.position[0]-motionTarget.position[0])/seconds,(data.position[1]-motionTarget.position[1])/seconds];
    const metersPerSecond=Math.hypot(velocity[0]*Math.cos(data.position[1]*Math.PI/180),velocity[1])*111320;
    if(metersPerSecond<=70) motionVelocity=velocity;
  }
  if(!motionPosition || seconds>3) motionPosition=data.position.slice();
  if(!motionTarget) {motionHeading=data.heading;motionTurnVelocity=0;}
  // Freeze bearing immediately on stopping; never follow stationary course noise.
  // Older packets without speed retain their previous behavior.
  if (Number.isFinite(data.speed) && data.speed < 1.5) {data={...data,heading:motionHeading};motionTurnVelocity=0;}
  motionTarget=data;motionAt=now;
  updateEdgeBeacons();
  if(motionFrame===null) motionFrame=requestAnimationFrame(animateMotion);
};
// Keep directional sprites in one screen coordinate system. Mixing map rotation
// with viewport pitch lets globe projection/zoom change the apparent direction.
let markerBearing = null;
function markerRotation() {
  const bearing = map?.getBearing?.() ?? 0;
  return ['-', ['coalesce',['get','heading'],0], Number.isFinite(bearing) ? bearing : 0];
}
function syncMarkerBearing() {
  if (!ready) return;
  const bearing = map.getBearing?.() ?? 0;
  if (!Number.isFinite(bearing) || bearing === markerBearing) return;
  markerBearing = bearing;
  for (const layer of ['ccs-self','ccs-live-cars']) {
    map.setLayoutProperty(layer, 'icon-rotate', markerRotation());
  }
}
function currentPosition() { return latest.features.find(f => f.properties.kind === 'self')?.geometry.coordinates; }
function followOffset() {
  // Keep the driver at 68% of the map height without persistent camera padding.
  return [0, Math.round((map.getCanvas?.().clientHeight || 0) * .18)];
}
function follow() {
  const p = currentPosition();
  if (p) map.easeTo({center:p, zoom:Math.max(map.getZoom(),15),offset:followOffset(),padding:0,duration:900});
}
window.ccsSetFeatures = data => {
  latest = data;
  document.documentElement?.style.setProperty('--ccs-controls-top',Math.max(0,data.beaconInsets?.top || 0)+'px');
  if(!motionReceived) {
    const self=data.features.find(f=>f.properties.kind==='self');
    motionPosition=self?.geometry.coordinates||null; motionHeading=self?.properties.heading||0;
    if(ready) map.getSource('ccs-motion')?.setData(motionData());
  }
  const fixed=data.features.filter(f=>!['live','self','route'].includes(f.properties.kind));
  staticData=fixed.length===data.features.length?data:{type:'FeatureCollection',features:fixed};
  liveData={type:'FeatureCollection',features:data.features.filter(f=>['live','route'].includes(f.properties.kind))};
  const fixedKey=JSON.stringify(fixed), movingKey=JSON.stringify(liveData.features);
  startAlertAnimation();
  if (ready) {
    if(fixedKey!==staticSignature) {map.getSource('ccs').setData(staticData);staticSignature=fixedKey;}
    if(movingKey!==liveSignature) {map.getSource('ccs-live').setData(liveData);liveSignature=movingKey;}
    const camera=data.camera;
    if(camera && camera.revision !== cameraRevision) {
      cameraRevision=camera.revision; following=false;
      if(camera.bounds) {
        const [a,b]=camera.bounds;
        const east=a[0]+shortArc(b[0]-a[0]);
        const bounds=[[Math.min(a[0],east),Math.min(a[1],b[1])],[Math.max(a[0],east),Math.max(a[1],b[1])]];
        motionFollowing=false;following=false;gestureBlocked=true;syncFrameBudget();
        map.fitBounds(bounds,{padding:{top:100,bottom:160,left:45,right:45},bearing:0,pitch:0,maxZoom:15.6,duration:500});
      }
      else if(!motionFollowing && !manualTouchActive) map.easeTo({center:camera.center,zoom:camera.zoom,...(!gestureBlocked?{bearing:camera.bearing||0}:{}),duration:250});
    } else if(following) follow();
  }
};
window.ccsFollow = () => { if(!currentPosition() && !motionPosition) return;gestureBlocked=false; following = true;lastCameraSignature=null; syncFrameBudget(); if(!motionReceived) follow(); };
window.ccsWorld = () => { gestureBlocked=true; following = false; motionFollowing=false; syncFrameBudget(); notify('gesture'); map.easeTo({zoom:1.3,pitch:0,duration:1200}); };
window.ccsSetStyle = style => {
  if (!['dark','positron'].includes(style) || style===currentStyle) {notify('ready');return;}
  stopAlertAnimation(); currentStyle=style; ready=false;
  map.setStyle('https://tiles.openfreemap.org/styles/'+style);
};
let alertTimer=null, viewActive=true;
function stopAlertAnimation() { if(alertTimer!==null) clearInterval(alertTimer); alertTimer=null; }
window.ccsSetActive = active => {viewActive=!!active;document.documentElement?.classList.toggle('ccs-paused',!viewActive);syncFrameBudget();updateEdgeBeacons(); if(viewActive) startAlertAnimation(); else {stopAlertAnimation();stopMotion();}};
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
  policeBeaconFrame = Math.round(p*16);
  map.setLayoutProperty('ccs-police-badge','icon-image','ccs-police-'+policeBeaconFrame);
  map.setPaintProperty('ccs-sos-glow','circle-opacity',0.34+p*0.22);
  map.setPaintProperty('ccs-sos-core','circle-opacity',['step',['zoom'],0.82+p*0.14,14.2,0.18+p*0.12]);
  map.setPaintProperty('ccs-sos-core','circle-stroke-opacity',0.82+p*0.18);
}
function startAlertAnimation() {
  const visible=ready && viewActive && latest.features.some(f=> {
    if(!['police','sos'].includes(f.properties.kind)) return false;
    // Keep offscreen alerts animating only when their edge beacon is in range.
    if((motionFollowing || following) && motionPosition && beaconDistance(motionPosition,f.geometry.coordinates)<beaconRange(f.properties.kind)[0]) return true;
    if(!map.project) return true;
    const p=map.project(f.geometry.coordinates), canvas=map.getCanvas();
    return p.x>=-60 && p.x<=canvas.clientWidth+60 && p.y>=-60 && p.y<=canvas.clientHeight+60;
  });
  if(!visible) {stopAlertAnimation();return;}
  if(alertTimer!==null) return;
  animateAlerts(); alertTimer=setInterval(animateAlerts,100);
}
try {
  map = new maplibregl.Map({container:'map',style:'https://tiles.openfreemap.org/styles/dark',center:[24.1,56.95],zoom:6.5,maxZoom:18,attributionControl:false});
  map.addControl(new maplibregl.AttributionControl({compact:true}),'top-left');
  // Native compact controls own globe/follow; pinch gestures provide zoom.
  const browse = () => {gestureBlocked=true;following=false;motionFollowing=false;syncFrameBudget();updateEdgeBeacons();notify('gesture');};
  // Capture the second finger before MapLibre handles the pinch. Camera jumpTo
  // updates can otherwise interrupt zoomstart before it carries originalEvent.
  const surface=document.getElementById('map');
  const touch = e => {
    manualTouchActive=e.touches.length>0;
    syncFrameBudget();
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
    for (const [key,pixels] of iconCache) {
      if(!key.includes('@beacon-')) map.addImage(key,pixels,{pixelRatio:2});
    }
    map.addSource('ccs',{type:'geojson',data:staticData});
    map.addSource('ccs-live',{type:'geojson',data:liveData});
    staticSignature=JSON.stringify(staticData.features);liveSignature=JSON.stringify(liveData.features);lastMotionSignature=null;
    map.addSource('ccs-motion',{type:'geojson',data:motionData()});
    map.addLayer({id:'ccs-restricted',type:'fill',source:'ccs',filter:['==',['get','kind'],'restricted'],paint:{'fill-color':'#ff5252','fill-opacity':0.16}});
    map.addLayer({id:'ccs-pin',type:'symbol',source:'ccs',filter:['==',['get','kind'],'pin'],layout:{
      'icon-image':['coalesce',['get','icon'],'ccs-pin-blue'],'icon-size':56/64,'icon-anchor':'bottom',
      'icon-allow-overlap':true,'icon-ignore-placement':true,'icon-pitch-alignment':'viewport','icon-rotation-alignment':'viewport'}});
    map.addLayer({id:'ccs-route',type:'line',source:'ccs-live',filter:['==',['get','kind'],'route'],paint:{'line-color':'#008dff','line-width':3,'line-dasharray':[2,2]}});
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
    map.addLayer({id:'ccs-live-cars',type:'symbol',source:'ccs-live',filter:['==',['get','kind'],'live'],layout:{
      'icon-image':['coalesce',['get','icon'],'assets/user_cars/car_green.png'],'icon-size':carSize,
      'icon-rotate':markerRotation(),'icon-rotation-alignment':'viewport',
      'icon-pitch-alignment':'viewport','icon-allow-overlap':true,'icon-ignore-placement':true}});
    map.addLayer({id:'ccs-cameras',type:'symbol',source:'ccs',minzoom:13,filter:['==',['get','kind'],'camera'],layout:{'icon-image':'ccs-speed-camera','icon-size':0.5,'icon-allow-overlap':true},paint:{'icon-opacity':['interpolate',['linear'],['zoom'],13,0,13.25,0.074,13.5,0.259,13.75,0.5,14,0.741,14.25,0.926,14.5,1]}});
    map.addLayer({id:'ccs-self',type:'symbol',source:'ccs-motion',filter:['==',['get','kind'],'self'],layout:{
      'icon-image':'ccs-self-arrow','icon-size':['interpolate',['linear'],['zoom'],3,18/64,16,62/64],
      'icon-rotate':markerRotation(), 'icon-rotation-alignment':'viewport',
      'icon-pitch-alignment':'viewport','icon-allow-overlap':true,'icon-ignore-placement':true}});
    addAlertLayers();
    const labelFont=map.getStyle().layers.find(l=>l.layout?.['text-font'])?.layout['text-font'] || ['Noto Sans Regular'];
    map.addLayer({id:'ccs-labels',type:'symbol',source:'ccs',filter:['all',['==',['geometry-type'],'Point'],['!=',['get','kind'],'self'],['!=',['get','kind'],'camera']],minzoom:12.35,layout:{
      'text-font':labelFont,'text-field':['get','label'],
      'text-size':['interpolate',['linear'],['zoom'],11.25,8.2,16,10],
      'text-anchor':'bottom','text-offset':[0,-4]},
      paint:{'text-color':currentStyle==='positron'?'#182333':'#ffffff','text-halo-color':currentStyle==='positron'?'#ffffff':'#101827','text-halo-width':2,
        'text-opacity':['interpolate',['linear'],['zoom'],12.35,0,14.25,1]}});
    ready=true; markerBearing=null; syncMarkerBearing(); statusBox.hidden=true; notify('ready'); startAlertAnimation(); collapseInitialAttribution();
  });
  map.on('rotate', syncMarkerBearing);
  map.on('click', e => {
    if(!ready) return;
    if(latest.routePreview) {
      latest.routePreview=false;
      notify('dismissRoute');
      return;
    }
    if(e.lngLat) notify('pick',{lat:e.lngLat.lat,lng:e.lngLat.lng});
    const p=map.queryRenderedFeatures(e.point,{layers:['ccs-cameras','ccs-spot-icons','ccs-points','ccs-live-cars','ccs-police-core','ccs-sos-core','ccs-police-badge','ccs-sos-badge']})[0]?.properties;
    if(p && p.kind!=='self') notify('select',{kind:p.kind,id:p.id});
    else if(!p) notify('clear');
  });
} catch (_) {statusBox.textContent='This device could not start the globe. Please retry.';notify('error');}

// One lightweight overlay update per 100 ms; CSS interpolates movement and fade.
// Only already-authorized, currently visible marker data can become beacons.
const edgeBeacons = new Map();
let beaconLayer;
function updateEdgeBeacons() {
  if (!document.createElement || !map?.project) return;
  if (!beaconLayer) {
    beaconLayer = document.createElement('div');
    beaconLayer.id = 'ccs-beacons';
    document.body.appendChild(beaconLayer);
  }
  beaconLayer.dataset.theme=currentStyle==='positron'?'light':'dark';
  const selected = new Set();
  const position = motionPosition || currentPosition();
  if (ready && viewActive && (motionFollowing || following) && !gestureBlocked && position && !latest.routePreview) {
    const canvas = map.getCanvas(), width = canvas.clientWidth, height = canvas.clientHeight;
    const inset = latest.beaconInsets || {top: 110, bottom: 12};
    const hasPeople=latest.features.some(f=>f.properties.kind==='live');
    const sideInset=hasPeople?54:30;
    const bounds = {left: sideInset, right: width - sideInset, top: inset.top + (hasPeople ? 62 : 46), bottom: height - inset.bottom - 30};
    if (bounds.right > bounds.left && bounds.bottom > bounds.top) {
      const projected = map.project(position);
      const origin = {x: Math.max(bounds.left, Math.min(bounds.right, projected.x)), y: Math.max(bounds.top, Math.min(bounds.bottom, projected.y))};
      const candidates = latest.features.filter(f => ['spot','live','camera','police','sos'].includes(f.properties.kind) && f.geometry.type === 'Point')
        .map(f => ({f, distance: beaconDistance(position, f.geometry.coordinates)}))
        .filter(item => Number.isFinite(item.distance) && item.distance < beaconRange(item.f.properties.kind)[0])
        .sort((a,b) => a.distance - b.distance || String(a.f.properties.id).localeCompare(String(b.f.properties.id)));
      const occupied = [];
      for (const {f, distance} of candidates) {
        if (selected.size >= 8) break;
        const p = f.properties, coordinate = f.geometry.coordinates;
        const point = map.project([position[0] + shortArc(coordinate[0] - position[0]), coordinate[1]]);
        // Do not duplicate markers already visible in the unobstructed map area.
        if (point.x >= 0 && point.x <= width && point.y >= inset.top && point.y <= height - inset.bottom) continue;
        const at = beaconPlacement(origin, point, bounds);
        if (at && ((at.x < 75 && at.y > height-110) || (at.x > width-75 && at.y > height-110))) continue;
        if (!at || occupied.some(other => Math.hypot(other.x-at.x, other.y-at.y) < (p.kind==='live'||other.person?104:66))) continue;
        const key = p.kind + ':' + p.id;
        let node = edgeBeacons.get(key);
        if (!node) {
          node = document.createElement('button'); node.className = 'ccs-beacon';
          const face = document.createElement('canvas'); face.width=128; face.height=128;
          if(p.kind==='live') {
            node.className+=' ccs-person-beacon';
            const name=document.createElement('strong');name.className='ccs-beacon-name';
            node.appendChild(name);node.nickname=name;
          }
          if(p.kind==='camera') {
            node.className+=' ccs-camera-beacon';
            const waves=document.createElement('i');waves.className='ccs-camera-waves';
            waves.setAttribute('aria-hidden','true');node.appendChild(waves);
          }
          node.face=face;
          const label = document.createElement('span');
          node.appendChild(face); node.appendChild(label);
          node.addEventListener('click', e => {e.stopPropagation(); notify('select', {kind:p.kind,id:p.id});});
          beaconLayer.appendChild(node); edgeBeacons.set(key,node);
          // Establish the transparent initial state before starting the fade.
          node.getBoundingClientRect();
        }
        if(p.kind==='camera') {
          const fresh=motionTarget?.gpsFresh===true && performance.now()-motionAt<1500;
          node.dataset.attention=String(fresh && cameraAhead(position,coordinate,motionHeading,motionTarget?.speed));
        }
        // Reuse the original inner category artwork in both beacon themes.
        if(node.nickname) node.nickname.textContent=String(p.label || 'User');
        const baseIcon = p.kind === 'live' ? (p.avatarIcon || 'ccs-person') : p.kind === 'police' ? 'ccs-police-' + policeBeaconFrame : p.kind === 'sos' ? 'ccs-sos' : p.icon;
        const theme=currentStyle==='positron'?'light':'dark';
        const artworkTheme=p.tint?(p.event?'event':'muted'):theme;
        const extracted=p.icon+'@beacon-'+artworkTheme;
        const icon = p.kind==='spot' && iconCache.has(extracted) ? extracted : baseIcon + (p.tint ? '@' + p.color : '');
        const pixels = iconCache.get(icon);
        if (pixels && node.dataset.icon !== icon) {
          node.face.getContext('2d').putImageData(pixels,0,0); node.dataset.icon=icon;
        }
        if (!pixels) continue;
        node.style.setProperty('--beacon-color', p.kind === 'sos' ? '#ff3355' : p.kind === 'police' ? (policeBeaconFrame < 8 ? '#1565ff' : '#ff2d55') : /^#[0-9a-f]{6}$/i.test(p.color || '') ? p.color : '#00b8ff');
        node.lastChild.textContent = (distance / 1000).toFixed(1) + ' km';
        node.setAttribute('aria-label', String(p.label || p.kind) + ', ' + node.lastChild.textContent);
        node.style.transform = `translate(${at.x}px,${at.y}px) translate(-50%,-50%)`;
        node.style.setProperty('--beacon-angle', (Math.atan2(point.y-origin.y,point.x-origin.x)*180/Math.PI+90)+'deg');
        node.style.opacity = String(beaconOpacity(distance, p.kind));
        node.style.pointerEvents = beaconOpacity(distance, p.kind) > 0.02 ? 'auto' : 'none';
        node.hiddenAt = null;
        selected.add(key); occupied.push({...at,person:p.kind==='live'});
      }
    }
  }
  const now = performance.now();
  for (const [key,node] of edgeBeacons) {
    if (selected.has(key)) continue;
    node.style.opacity='0'; node.style.pointerEvents='none';node.dataset.attention='false';
    if (node.hiddenAt == null) node.hiddenAt=now;
    if (now-node.hiddenAt>500) {node.remove();edgeBeacons.delete(key);}
  }
}
let lastBeaconUpdate = -Infinity;
map?.on('render', () => {
  const now = performance.now();
  if (now-lastBeaconUpdate < 100) return;
  lastBeaconUpdate=now;
  updateEdgeBeacons();
  startAlertAnimation();
});
