const { countryCode } = require('./private-groups');

function canModerateCountry(user, country, community = false) {
  if (!user || user.deleted === true || user.banned === true) return false;
  if (user.role === 'admin') return true;
  const code = countryCode(country);
  const eligible = user.role === 'moderator' || (community &&
    (user.globalModerator === true || user.globalChatModerator === true));
  return eligible && !!code && Array.isArray(user.moderatorCountryCodes) &&
    user.moderatorCountryCodes.includes(code);
}

// Only legacy community records without a country belong to Latvia.
function communityCountry(data) {
  return Object.hasOwn(data, 'countryCode') ? countryCode(data.countryCode) : 'LV';
}

module.exports = { canModerateCountry, communityCountry };
