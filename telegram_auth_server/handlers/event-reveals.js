const crypto = require('node:crypto');
const {db} = require('../lib/firebase-admin');
const {dispatchEventReveals} = require('../lib/event-reveal');
module.exports = async (req,res) => {
  if (req.method !== 'GET') return res.status(405).json({ok:false});
  const expected=process.env.EVENT_REVEAL_WORKER_SECRET;
  const provided=String(req.headers.authorization || '');
  const target='Bearer '+expected;
  if (!expected || Buffer.byteLength(provided)!==Buffer.byteLength(target) ||
      !crypto.timingSafeEqual(Buffer.from(provided),Buffer.from(target))) return res.status(401).json({ok:false});
  const since=Date.parse(process.env.EVENT_REVEAL_NOTIFICATIONS_SINCE || '');
  if (!Number.isFinite(since) || since<=0) return res.status(503).json({ok:false,error:'Reveal scheduler activation date missing'});
  try {
    const {sendPushToUser,countryKey}=await import('../api/push-notification.js');
    const result=await dispatchEventReveals({db,send:sendPushToUser,countryKey,since});
    return res.status(200).json(result);
  } catch (_) { return res.status(500).json({ok:false,error:'Reveal dispatch deferred'}); }
};
