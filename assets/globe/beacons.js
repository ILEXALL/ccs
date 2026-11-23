const radians = value => value * Math.PI / 180;
// Keep the entire beacon (including labels, arrow and radar waves) inside
// the clear band between native Flutter overlays. Never drop corner beacons.
function beaconSafeBounds(width, height, inset, hasPeople) {
  // A stable rail: nearby people arriving/leaving must not move every beacon.
  const side = 58;
  return {left:side,right:width-side,top:inset.top+66,bottom:height-inset.bottom-50};
}
if (typeof module !== 'undefined') module.exports.beaconSafeBounds = beaconSafeBounds;
function beaconDistance(a, b) {
  const lat = radians(b[1] - a[1]), lng = radians(b[0] - a[0]);
  const h = Math.sin(lat / 2) ** 2 + Math.cos(radians(a[1])) * Math.cos(radians(b[1])) * Math.sin(lng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
function beaconRange(kind) {
  return kind === 'sos' ? [5000, 1000] : kind === 'camera' ? [500, 200] : [2000, 500];
}
function beaconOpacity(distance, kind = 'spot') {
  const [start, end] = beaconRange(kind);
  const t = Math.max(0, Math.min(1, (start - distance) / (start - end)));
  return t * t * (3 - 2 * t);
}
function beaconPlacement(origin, point, bounds) {
  if (point.x >= bounds.left && point.x <= bounds.right && point.y >= bounds.top && point.y <= bounds.bottom) return null;
  const dx = point.x - origin.x, dy = point.y - origin.y;
  if (!Number.isFinite(dx + dy) || (!dx && !dy)) return null;
  const tx = dx > 0 ? (bounds.right - origin.x) / dx : dx < 0 ? (bounds.left - origin.x) / dx : Infinity;
  const ty = dy > 0 ? (bounds.bottom - origin.y) / dy : dy < 0 ? (bounds.top - origin.y) / dy : Infinity;
  const t = Math.min(tx, ty);
  return {x: origin.x + dx * t, y: origin.y + dy * t};
}
if (typeof module !== 'undefined') Object.assign(module.exports, {beaconDistance, beaconOpacity, beaconPlacement, beaconRange});

// A zoom difference of one doubles visible ground distance.
function speedFollowZoom(baseZoom, metersPerSecond) {
  const kmh = Number.isFinite(metersPerSecond) ? Math.max(0, metersPerSecond) * 3.6 : 0;
  const distanceScale = Math.min(5, 1 + Math.max(0, kmh - 30) / 35);
  return baseZoom - Math.log2(distanceScale);
}
if (typeof module !== 'undefined') module.exports.speedFollowZoom = speedFollowZoom;

// Geographic forward cone: independent of the manually rotated map camera.
function cameraAhead(origin, target, heading, speed) {
  if(!origin || !target || ![...origin,...target,heading,speed].every(Number.isFinite) || speed<1.5) return false;
  const a=radians(origin[1]),b=radians(target[1]),dl=radians(target[0]-origin[0]);
  const bearing=Math.atan2(Math.sin(dl)*Math.cos(b),Math.cos(a)*Math.sin(b)-Math.sin(a)*Math.cos(b)*Math.cos(dl))*180/Math.PI;
  return Math.abs(((bearing-heading+540)%360)-180)<=60;
}
if(typeof module!=='undefined') module.exports.cameraAhead=cameraAhead;

function beaconForwardOpacity(origin, target, heading) {
  if(!origin || !target || ![...origin,...target,heading].every(Number.isFinite)) return 0;
  const a=radians(origin[1]),b=radians(target[1]),dl=radians(target[0]-origin[0]);
  const bearing=Math.atan2(Math.sin(dl)*Math.cos(b),Math.cos(a)*Math.sin(b)-Math.sin(a)*Math.cos(b)*Math.cos(dl))*180/Math.PI;
  const angle=Math.abs(((bearing-heading+540)%360)-180);
  // Full opacity to 50 degrees, feather out at the edge of the 120-degree cone.
  const t=Math.max(0,Math.min(1,(60-angle)/10));
  return t*t*(3-2*t);
}
function beaconMarkerVisible(point, width, height) {
  // Include partially visible pin artwork. Native HUD occlusion is irrelevant:
  // a marker must leave the actual viewport before its beacon can appear.
  return Number.isFinite(point.x+point.y) && point.x+32>=0 && point.x-32<=width &&
    point.y+32>=0 && point.y-64<=height;
}
if(typeof module!=='undefined') Object.assign(module.exports,{beaconForwardOpacity,beaconMarkerVisible});

// Cluster only offscreen people at the same physical place, not unrelated
// destinations that happen to point toward the same screen edge.
function groupPeopleBeacons(features, radius = 50) {
  const other = features.filter(f => f.properties.kind !== 'live');
  const people = features.filter(f => f.properties.kind === 'live')
    .slice().sort((a,b) => String(a.properties.id).localeCompare(String(b.properties.id)));
  const groups = [];
  for (const person of people) {
    let group = groups.find(g => beaconDistance(g[0].geometry.coordinates, person.geometry.coordinates) <= radius);
    if (!group) {group=[];groups.push(group);}
    group.push(person);
  }
  for (const group of groups) {
    const first=group[0];
    if (group.length===1) {other.push(first);continue;}
    other.push({...first,properties:{...first.properties,
      memberIds:group.map(f=>f.properties.id),count:group.length,
      label:group.slice(0,3).map(f=>f.properties.label || 'User').join(', ')+(group.length>3?' +'+(group.length-3):'')}});
  }
  return other;
}
if(typeof module!=='undefined') module.exports.groupPeopleBeacons=groupPeopleBeacons;
// Project a short ground probe toward the destination. A distant ground point
// behind a pitched camera can have negative perspective depth and flip by 180°.
function beaconScreenDirection(origin, target, project) {
  const a=radians(origin[1]),b=radians(target[1]);
  const dl=radians(((target[0]-origin[0]+540)%360)-180);
  const bearing=Math.atan2(Math.sin(dl)*Math.cos(b),Math.cos(a)*Math.sin(b)-Math.sin(a)*Math.cos(b)*Math.cos(dl));
  const distance=beaconDistance(origin,target);
  if(!Number.isFinite(distance)||distance<.1)return null;
  const step=Math.min(5,distance)/6371000;
  const lat=Math.asin(Math.sin(a)*Math.cos(step)+Math.cos(a)*Math.sin(step)*Math.cos(bearing));
  const lng=radians(origin[0])+Math.atan2(Math.sin(bearing)*Math.sin(step)*Math.cos(a),Math.cos(step)-Math.sin(a)*Math.sin(lat));
  const start=project(origin),near=project([lng*180/Math.PI,lat*180/Math.PI]);
  const dx=near.x-start.x,dy=near.y-start.y,length=Math.hypot(dx,dy);
  if(!Number.isFinite(length)||length<1e-8)return null;
  const point=project([origin[0]+((target[0]-origin[0]+540)%360)-180,target[1]]);
  return {dx:dx/length,dy:dy/length,point,inFront:(point.x-start.x)*dx+(point.y-start.y)*dy>=0};
}
if(typeof module!=='undefined')module.exports.beaconScreenDirection=beaconScreenDirection;
