'use strict';
// Connected components of overlapping screen-space marker rectangles. Input is
// already filtered for visibility/access; no event can disappear from a group.
function groupEventPoints(points, width, height) {
  const parents=points.map((_,i)=>i),cells=new Map();
  const root=i=>{while(parents[i]!==i){parents[i]=parents[parents[i]];i=parents[i];}return i;};
  points.forEach((p,i)=>{
    const x=Math.floor(p.x/width),y=Math.floor(p.y/height);
    for(let dx=-1;dx<=1;dx++) for(let dy=-1;dy<=1;dy++)
      for(const j of cells.get(`${x+dx},${y+dy}`)||[])
        if(Math.abs(p.x-points[j].x)<width && Math.abs(p.y-points[j].y)<height) parents[root(i)]=root(j);
    const key=`${x},${y}`;if(!cells.has(key))cells.set(key,[]);cells.get(key).push(i);
  });
  const groups=new Map();points.forEach((p,i)=>{const r=root(i);if(!groups.has(r))groups.set(r,[]);groups.get(r).push(p);});
  return [...groups.values()];
}
if(typeof module!=='undefined')module.exports={groupEventPoints};

function eventMarkerMetrics(zoom) {
  const city=zoom<=7?1:zoom<9?1-(zoom-7)*.1:zoom<=12?.8:Math.min(1,.8+(zoom-12)*(.2/3));
  const dot=zoom<11.25;
  const p=Math.max(0,Math.min(1,dot?(zoom-3)/8.25:(zoom-11.25)/4.75));
  const width=dot?(3.2+7.2*Math.pow(p,2.7))*city:(38+27*(1-Math.pow(1-p,3)))*city;
  return {dot,width,height:dot?width:width*36/128+(zoom>=14?32:0),showTime:!dot&&zoom>=14};
}
if(typeof module!=='undefined')module.exports.eventMarkerMetrics=eventMarkerMetrics;
