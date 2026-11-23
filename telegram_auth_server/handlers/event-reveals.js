const crypto = require('node:crypto');
const {db} = require('../lib/firebase-admin');
const {dispatchEventNotifications} = require('../lib/event-reveal');
const {dispatchForumInactivity} = require('../lib/forum-inactivity');
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
    const result=await dispatchEventNotifications({db,send:sendPushToUser,countryKey,since,budgetMs:30000});
    const forum=await dispatchForumInactivity({db,send:sendPushToUser});
    return res.status(200).json({...result,forum});
  } catch (_) { return res.status(500).json({ok:false,error:'Reveal dispatch deferred'}); }
};
