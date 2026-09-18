// Keep the public URLs stable while sharing one Vercel function.
const handlers = new Map([
  ['xp-sync', require('../handlers/xp-sync')],
  ['xp-leaderboard', require('../handlers/xp-leaderboard')],
  ['spot-visit', require('../handlers/spot-visit')],
]);

module.exports = (req, res) => {
  const handler = handlers.get(req.query?.endpoint);
  if (!handler) return res.status(404).json({ok: false, error: 'Unknown endpoint'});
  return handler(req, res);
};
