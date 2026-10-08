const radians = value => value * Math.PI / 180;
function beaconDistance(a, b) {
  const lat = radians(b[1] - a[1]), lng = radians(b[0] - a[0]);
  const h = Math.sin(lat / 2) ** 2 + Math.cos(radians(a[1])) * Math.cos(radians(b[1])) * Math.sin(lng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
function beaconOpacity(distance) {
  const t = Math.max(0, Math.min(1, (2000 - distance) / 1500));
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
if (typeof module !== 'undefined') module.exports = {beaconDistance, beaconOpacity, beaconPlacement};
