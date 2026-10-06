// Keep the public URLs stable while sharing one Vercel function.
const handlers = new Map([
  ['partner-view', require('../handlers/partner-view')],
  ['create-spot', require('../handlers/create-spot')],
  ['account-deletion', (req, res) => require('../handlers/account-deletion')(req, res)],
  ['xp-sync', require('../handlers/xp-sync')],
  ['xp-leaderboard', require('../handlers/xp-leaderboard')],
  ['spot-visit', require('../handlers/spot-visit')],
]);

module.exports = (req, res) => {
  res.setHeader('X-CCS-Rewards-Version', 'weekly-live-v1');
  const handler = handlers.get(req.query?.endpoint);
  if (!handler) return res.status(404).json({ok: false, error: 'Unknown endpoint'});
  return handler(req, res);
};
