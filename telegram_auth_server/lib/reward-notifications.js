const {admin, db} = require('./firebase-admin');
function rewardReason(input) {
  const reasons = {
    'event.attended': 'Event attended', 'spot.approved': 'Permanent spot approved',
    'spot.description': 'Spot description', 'spot.photo': 'Spot photo', 'spot.media_bundle': 'Spot media',
    'profile.avatar': 'Profile photo added', 'profile.bio': 'Profile bio completed',
    'profile.city': 'Profile location completed', 'profile.social': 'Social profile added',
    'profile.full': 'Profile completed', 'garage.first_car': 'First car added',
    'garage.first_car_photo': 'First car photo', 'garage.first_car_description': 'Car description',
    'garage.first_car_gallery': 'Car gallery completed',
  };
  if (input.metadata?.reason) return String(input.metadata.reason).slice(0, 180);
  if (input.action === 'achievement.unlock') return `Achievement unlocked: ${input.objectId}`;
  return reasons[input.action] || input.action.replaceAll('.', ' ').replaceAll('_', ' ');
}
async function deliverRewardPush(input, result) {
  const id = `xp_${result.transactionId}`;
  const notification = (await db.collection('user_notifications').doc(id).get()).data();
  if (!notification) return; // Honors the XP notification preference.
  const {sendPushToUser} = await import('../api/push-notification.js');
  await sendPushToUser({userId: input.userId, title: notification.title, body: notification.body,
    settingName: 'xpNotifications', notificationId: id, deliveryKey: id,
    data: {type: 'xp_reward', xpAction: input.action, xpAmount: result.amount,
      xpObjectId: input.objectId, notificationId: id, levelUp: notification.levelUp || ''}});
}
module.exports = {rewardReason, deliverRewardPush};
