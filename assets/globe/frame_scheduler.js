/* This dedicated WebView owns its animation frames. Install before MapLibre so
 * camera gestures and marker interpolation share the same 30/60 FPS budget. */
'use strict';
(() => {
  const request = window.requestAnimationFrame.bind(window);
  const cancel = window.cancelAnimationFrame.bind(window);
  const callbacks = new Map();
  let sequence=0, pending=null, last=-Infinity, fps=60, active=true;
  function schedule() {
    if(active && pending===null && callbacks.size) pending=request(tick);
  }
  function tick(now) {
    pending=null;
    if(now-last >= 1000/fps-.25) {
      last=now;
      const batch=[...callbacks.keys()];
      for(const id of batch) {
        const callback=callbacks.get(id);
        if(!callback) continue;
        callbacks.delete(id);
        try {callback(now);} catch(error) {setTimeout(()=>{throw error;},0);}
      }
    }
    schedule();
  }
  window.requestAnimationFrame = callback => {
    const id=++sequence; callbacks.set(id,callback); schedule(); return id;
  };
  window.cancelAnimationFrame = id => {
    callbacks.delete(id);
    if(!callbacks.size && pending!==null) {cancel(pending);pending=null;}
  };
  window.ccsFrameBudget = (following, visible=true) => {
    fps=following?30:60; active=!!visible;
    if(!active && pending!==null) {cancel(pending);pending=null;}
    if(active) schedule();
  };
})();
