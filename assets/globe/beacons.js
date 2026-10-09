const radians = value => value * Math.PI / 180;
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
if (typeof module !== 'undefined') module.exports = {beaconDistance, beaconOpacity, beaconPlacement, beaconRange};

// A zoom difference of one doubles visible ground distance.
function speedFollowZoom(baseZoom, metersPerSecond) {
  const kmh = Number.isFinite(metersPerSecond) ? Math.max(0, metersPerSecond) * 3.6 : 0;
  const distanceScale = Math.min(3, 1 + Math.max(0, kmh - 30) / 70);
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
