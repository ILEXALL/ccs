const {db} = require('./firebase-admin');

// Called only after the membership transaction succeeds. Delivery uses the
// existing preference checks, token cleanup and deduplication in the push service.
async function notifyGroupMembers(chatId, actorUid, userIds, accepted = false, send) {
  if (!userIds?.length) return;
  const chatDoc = await db.collection('chats').doc(chatId).get();
  const chat = chatDoc.data();
  if (!chat || chat.isGroup !== true) return;
  const deliver = send || (await import('../api/push-notification.js')).sendPushToUser;
  const version = chat.updatedAt?.toMillis?.() ?? chat.updatedAt ?? 0;
  for (const userId of [...new Set(userIds)]) {
    if (userId === actorUid || !(chat.memberIds || []).includes(userId)) continue;
    const request = accepted ? (await db.collection('chats').doc(chatId).collection('join_requests').doc(userId).get()).data() : null;
    if (accepted && request?.status !== 'accepted') continue;
    const deliveryVersion = accepted ? (request.decidedAt?.toMillis?.() ?? request.decidedAt ?? 0) : version;
    const type = accepted ? 'group_join_decision' : 'group_members_added';
    await deliver({userId, settingName: 'friendRequestNotifications',
      deliveryKey: `${type}:${chatId}:${userId}:${deliveryVersion}`,
      ...(accepted ? {notificationId: `group_decision_${chatId}_${userId}`} : {}),
      title: accepted ? 'Group request approved' : 'Added to a group',
      body: accepted ? `Your request to join ${chat.name || 'the group'} was approved.`
        : `You have been added to ${chat.name || 'a group'}.`,
      data: {type, chatId, status: 'accepted'},
    });
  }
}
module.exports = {notifyGroupMembers};
