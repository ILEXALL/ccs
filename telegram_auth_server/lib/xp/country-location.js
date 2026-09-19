const boundaries = require('./country-boundaries');
function insideRing(lng, lat, ring) {
  let inside = false;
  for (let i=0,j=ring.length-1;i<ring.length;j=i++) {
    const [x,y]=ring[i], [px,py]=ring[j];
    if ((y>lat)!==(py>lat) && lng < (px-x)*(lat-y)/(py-y)+x) inside=!inside;
  }
  return inside;
}
function nearRing(lng, lat, ring) {
  const xScale=111320*Math.cos(lat*Math.PI/180), yScale=111320;
  for(let i=0,j=ring.length-1;i<ring.length;j=i++){
    const ax=(ring[j][0]-lng)*xScale, ay=(ring[j][1]-lat)*yScale;
    const bx=(ring[i][0]-lng)*xScale, by=(ring[i][1]-lat)*yScale;
    const dx=bx-ax,dy=by-ay,denom=dx*dx+dy*dy;
    const t=denom?Math.max(0,Math.min(1,-(ax*dx+ay*dy)/denom)):0;
    if(Math.hypot(ax+t*dx,ay+t*dy)<=10000)return true;
  }
  return false;
}
function countryForCoordinates(lat, lng, hint) {
  // Native geocoding resolves coastal/border discrepancies in generalized
  // map outlines. Only accept a supported hint corroborated by those outlines.
  const hinted=boundaries.find(c=>c.code===hint);
  if(hinted?.polygons.some(p=>insideRing(lng,lat,p[0])&&!p.slice(1).some(r=>insideRing(lng,lat,r)) || nearRing(lng,lat,p[0])))return hinted.code;
  for (const country of boundaries) for (const polygon of country.polygons) {
    if (insideRing(lng,lat,polygon[0]) && !polygon.slice(1).some(r=>insideRing(lng,lat,r))) return country.code;
  }
  return null;
}
function validateCountryFix(input, now = Date.now()) {
  const {latitude,longitude,accuracy,recordedAtMillis}=input;
  if (![latitude,longitude,accuracy,recordedAtMillis].every(v=>typeof v==='number'&&Number.isFinite(v)) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 ||
      accuracy < 0 || accuracy > 1000 || now-recordedAtMillis > 5*60*1000 || recordedAtMillis-now > 60*1000 || input.isMocked === true) {
    throw new Error('A fresh GPS location is required');
  }
  return countryForCoordinates(latitude,longitude,input.countryCode);
}
module.exports = {countryForCoordinates,validateCountryFix};
