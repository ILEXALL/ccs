// Independent of account deletion. No Firebase credentials are stored here.
export default {
  async scheduled(_event, env) {
    if (env.ENABLED !== 'true') return;
    if (!env.EVENT_REVEAL_WORKER_SECRET) throw new Error('Reveal scheduler secret missing');
    const response=await fetch('https://ccs-wine.vercel.app/api/community?endpoint=event-reveals', {
      headers:{Authorization:`Bearer ${env.EVENT_REVEAL_WORKER_SECRET}`},
      redirect:'manual',signal:AbortSignal.timeout(55000),
    });
    if (!response.ok) throw new Error(`Reveal scheduler HTTP ${response.status}`);
    const result=await response.json();
    if (result.ok!==true) throw new Error('Reveal scheduler failed');
    console.log(JSON.stringify({ok:true,processed:Number(result.processed || 0),busy:result.busy===true}));
  },
  async fetch() {return new Response('Not found',{status:404});},
};
