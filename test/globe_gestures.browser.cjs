// Local browser integration against the bundled MapLibre, with no basemap/network.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{spawn}=require('node:child_process');
const root=path.resolve(__dirname,'../assets/globe');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const server=http.createServer((req,res)=>{
  if(req.url==='/') {res.setHeader('content-type','text/html');res.end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/maplibre-gl.css"><link rel="stylesheet" href="/globe.css"><div id="map"></div><div id="status"></div><script src="/maplibre-gl.js"></script><script>window.CcsGlobe={postMessage(){}};const RealMap=maplibregl.Map;maplibregl.Map=class extends RealMap{constructor(o){super({...o,style:{version:8,sources:{},layers:[]},center:[24,57],zoom:14});window.testMap=this;}};</script><script src="/beacons.js"></script><script src="/event_clusters.js"></script><script src="/globe.js"></script>`);return;}
  const name=path.basename(req.url.split('?')[0]);const file=path.join(root,name);
  if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}
  res.setHeader('content-type',name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'image/png');let contents=fs.readFileSync(file);if(name==='globe.js'&&process.env.CCS_TEST_LEGACY_GESTURES==='1'){contents=contents.toString().replace('// Never mutate the camera from gesture-start handlers: MapLibre owns it.','map.stop();map.jumpTo({pitch:0});').replace("  map.on('idle',","  map.on('pitch',()=>{if(gestureBlocked && !motionFollowing && testMap.getPitch()!==0) testMap.jumpTo({pitch:0});});\n  map.on('idle',");}res.end(contents);
 });await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const temp=fs.mkdtempSync('G:/Codex/Temp/ccs-map-browser-');
 const browser=spawn(process.env.CCS_BROWSER||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu-sandbox','--no-first-run','--remote-debugging-port=0','--user-data-dir='+temp,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let ws;try {
  let port;for(let i=0;i<100;i++){try{port=fs.readFileSync(path.join(temp,'DevToolsActivePort'),'utf8').split('\n')[0];break;}catch{}await delay(100);}assert.ok(port,'browser debugging port');
  const targets=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
  let id=0;const pending=new Map();ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}});
  const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});ws.send(JSON.stringify({id:key,method,params}));});
  const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
  await send('Emulation.setDeviceMetricsOverride',{width:400,height:800,deviceScaleFactor:1,mobile:true});await send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:5});await send('Page.navigate',{url:'http://127.0.0.1:'+server.address().port});
  for(let i=0;i<100;i++){if(await evaluate('!!window.testMap && testMap.isStyleLoaded()'))break;await delay(100);}await delay(200);
  const pinch=async(start,end)=>{
    const points=d=>[{x:200-d/2,y:400,id:1},{x:200+d/2,y:400,id:2}];
    await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:points(start)});
    for(let i=1;i<=15;i++){await send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:points(start+(end-start)*i/15)});await delay(20);}
    await send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await delay(700);
  };
  await evaluate('testMap.jumpTo({zoom:14,pitch:0});void 0');const initial=await evaluate('testMap.getZoom()');await pinch(90,230);const zoomIn=await evaluate('testMap.getZoom()');assert.ok(zoomIn>initial+.3,`pinch in ${initial} -> ${zoomIn}`);
  await pinch(230,90);const zoomOut=await evaluate('testMap.getZoom()');assert.ok(zoomOut<zoomIn-.3,`pinch out ${zoomIn} -> ${zoomOut}`);
  await evaluate('window.ccsSetMotion({position:[24,57],heading:60,speed:0,following:true,followRevision:1,zoom:14})');await delay(650);assert.ok((await evaluate('testMap.getPitch()'))>44);
  await evaluate('window.pitchSamples=[];testMap.on("pitch",()=>pitchSamples.push(testMap.getPitch()));void 0');const before=await evaluate('testMap.getZoom()');await pinch(90,230);for(let i=0;i<30 && await evaluate('testMap.getPitch()>.1');i++)await delay(100);const after=await evaluate('({zoom:testMap.getZoom(),pitch:testMap.getPitch(),bearing:testMap.getBearing()})');assert.ok(after.zoom>before+.3,'pinch exits follow and zooms');assert.ok(after.pitch<.1,'smooth flatten settles');assert.ok(await evaluate('pitchSamples.some(p=>p>1&&p<44)'), 'flatten has intermediate pitch frames');
  await evaluate('window.ccsSetMotion({position:[24,57],heading:60,speed:0,following:true,followRevision:1,zoom:14})');await delay(200);assert.ok(Math.abs((await evaluate('testMap.getZoom()'))-after.zoom)<.01,'stale packet cannot override pinch');
  await evaluate('window.ccsSetMotion({position:[24,57],heading:60,speed:0,following:true,followRevision:2,zoom:14})');await delay(100);const intermediate=await evaluate('testMap.getPitch()');assert.ok(intermediate>0&&intermediate<44,'follow pitch eases through intermediate values');await delay(550);assert.ok((await evaluate('testMap.getPitch()'))>44);
  await evaluate(`window.ccsSetMotion({following:false,followRevision:2,position:[24,57],heading:60,speed:0,zoom:14});testMap.jumpTo({center:[24,57],zoom:16,pitch:0,bearing:0});window.ccsSetFeatures({features:[{properties:{kind:'spot',id:'event',event:true,eventTimeLabel:'20.11\\n19:00'},geometry:{type:'Point',coordinates:[24,57]}}]});void 0`);await delay(150);
  const large=await evaluate(`({width:document.querySelector('.ccs-event-capsule img').getBoundingClientRect().width,time:document.querySelector('.ccs-event-capsule span').textContent})`);assert.equal(large.width,65);assert.equal(large.time,'20.11\n19:00');
  await evaluate('testMap.jumpTo({zoom:6});void 0');await delay(150);
  const dot=await evaluate(`(()=>{const n=document.querySelector('.ccs-event-dot');return {width:n.querySelector('i').getBoundingClientRect().width,color:getComputedStyle(n.querySelector('i')).backgroundColor,time:n.querySelector('span').textContent,hitWidth:n.getBoundingClientRect().width}})()`);assert.ok(dot.width<5);assert.equal(dot.color,'rgb(20, 87, 239)');assert.equal(dot.time,'');assert.equal(dot.hitWidth,44);
  const directions=await evaluate(`(()=>{
    const failures=[];let reversed=0,cases=0;
    function target(o,b,d){const r=Math.PI/180,a=o[1]*r,l=o[0]*r,t=b*r,q=d/6371000;const p=Math.asin(Math.sin(a)*Math.cos(q)+Math.cos(a)*Math.sin(q)*Math.cos(t));return [(l+Math.atan2(Math.sin(t)*Math.sin(q)*Math.cos(a),Math.cos(q)-Math.sin(a)*Math.sin(p)))/r,p/r];}
    for(const origin of [[24,57],[179.999,0]])for(const pitch of [0,45])for(const bearing of [0,45,90,179,270,359])for(let heading=0;heading<360;heading+=45){
      testMap.jumpTo({center:origin,pitch,bearing,zoom:16});
      const dest=target(origin,heading,10000),ray=beaconScreenDirection(origin,dest,p=>testMap.project(p));
      const near=target(origin,heading,1),o=testMap.project(origin),n=testMap.project(near);
      const dot=ray.dx*(n.x-o.x)+ray.dy*(n.y-o.y);cases++;
      if(!(dot>0))failures.push({origin,pitch,bearing,heading});
      if(!ray.inFront)reversed++;
    }
    return {cases,reversed,failures};
  })()`);
  assert.equal(directions.failures.length,0,JSON.stringify(directions.failures));assert.ok(directions.reversed>0,'reproduces far-point perspective reversal');
  console.log(JSON.stringify({passed:true,initial,zoomIn,zoomOut,followExit:after,followIntermediatePitch:intermediate,capsule:large,dot,directions}));
  await send('Browser.close').catch(()=>{});
 }finally{ws?.close();browser.kill();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});


