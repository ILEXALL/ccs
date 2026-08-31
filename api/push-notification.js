import crypto from 'node:crypto';
import admin from 'firebase-admin';

function serviceAccountFromEnvironment() {
  const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

  if (!rawJson) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not set.');
  }

  const serviceAccount = JSON.parse(rawJson);

  if (serviceAccount.private_key) {
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
  }

  return serviceAccount;
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccountFromEnvironment()),
  });
}

const db = admin.firestore();

const defaultNotificationSettings = {
  reviewNotifications: true,
  likeNotifications: true,
  commentNotifications: true,
  newSpotNotifications: true,
  newMessageNotifications: true,
  friendRequestNotifications: true,
  friendAtSpotNotifications: true,
  friendLiveShareNotifications: true,
};

function cleanText(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function shortText(value, fallback = '', maxLength = 140) {
  const text = cleanText(value, fallback);
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}...`;
}

function cleanStringArray(value, limit = 500) {
  if (!Array.isArray(value)) {
    return [];
  }

  return [
    ...new Set(
      value
        .filter((item) => typeof item === 'string')
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  ].slice(0, limit);
}

function settingEnabled(user, settingName) {
  const settings = user.settings || {};
  const fallback = defaultNotificationSettings[settingName] === true;

  if (typeof user[settingName] === 'boolean') {
    return user[settingName];
  }

  if (typeof settings[settingName] === 'boolean') {
    return settings[settingName];
  }

  return fallback;
}

function userTokens(user) {
  if (!Array.isArray(user.fcmTokens)) {
    return [];
  }

  return [...new Set(user.fcmTokens.filter((token) => typeof token === 'string' && token.trim()))];
}

function timestampToMillis(value) {
  if (value && typeof value.toMillis === 'function') {
    return value.toMillis();
  }

  if (value instanceof Date) {
    return value.getTime();
  }

  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function userHasActiveBan(user = {}) {
  if (user.banned !== true) {
    return false;
  }

  const bannedUntilMillis = timestampToMillis(user.bannedUntil);
  return !bannedUntilMillis || bannedUntilMillis > Date.now();
}

function deliveryId(deliveryKey, userId) {
  return crypto
    .createHash('sha256')
    .update(`${deliveryKey}|${userId}`)
    .digest('hex');
}

function spotNotificationOwnerUid(spot = {}) {
  return cleanText(spot.ownerUid, cleanText(spot.addedByUid));
}

function friendshipIdFor(firstUid, secondUid) {
  return [firstUid, secondUid].sort().join('_');
}

function userIsStaff(user = {}) {
  const role = cleanText(user.role);
  return role === 'admin' || role === 'moderator';
}

async function friendshipAccepted(firstUid, secondUid) {
  if (!firstUid || !secondUid || firstUid === secondUid) {
    return false;
  }

  const [firstRequest, secondRequest, friendship] = await Promise.all([
    db.collection('friend_requests').doc(`${firstUid}_${secondUid}`).get(),
    db.collection('friend_requests').doc(`${secondUid}_${firstUid}`).get(),
    db.collection('friendships').doc(friendshipIdFor(firstUid, secondUid)).get(),
  ]);

  if (firstRequest.exists && firstRequest.data()?.status === 'accepted') {
    return true;
  }

  if (secondRequest.exists && secondRequest.data()?.status === 'accepted') {
    return true;
  }

  if (!friendship.exists) {
    return false;
  }

  const userIds = cleanStringArray(friendship.data()?.userIds, 2);
  return userIds.includes(firstUid) && userIds.includes(secondUid);
}

async function claimDelivery(deliveryKey, userId) {
  const ref = db.collection('push_deliveries').doc(deliveryId(deliveryKey, userId));

  try {
    await ref.create({
      userId,
      deliveryKey,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref;
  } catch (error) {
    if (error.code === 6 || error.code === 'already-exists') {
      return null;
    }

    throw error;
  }
}

async function unreadNotificationCount(userId) {
  const userSnapshot = await db
    .collection('user_notifications')
    .where('userId', '==', userId)
    .where('read', '==', false)
    .get();
  let adminUnreadCount = 0;

  try {
    const adminSnapshot = await db
      .collection('admin_notifications')
      .where('userId', '==', userId)
      .where('read', '==', false)
      .get();
    adminUnreadCount = adminSnapshot.size;
  } catch (error) {
    console.warn('Admin unread count skipped:', error?.message || error);
  }

  return userSnapshot.size + adminUnreadCount;
}

async function sendPushToUser({
  userId,
  settingName,
  deliveryKey,
  notificationId,
  notificationCollection = 'user_notifications',
  title,
  body,
  data = {},
}) {
  if (!userId) {
    return 0;
  }

  const userRef = db.collection('users').doc(userId);
  const userSnapshot = await userRef.get();

  if (!userSnapshot.exists) {
    return 0;
  }

  const user = userSnapshot.data() || {};

  if (
    user.deleted === true ||
    userHasActiveBan(user) ||
    !settingEnabled(user, settingName)
  ) {
    return 0;
  }

  const deliveryRef = await claimDelivery(deliveryKey, userId);
  if (!deliveryRef) {
    return 0;
  }

  const notificationType = cleanText(data.type, 'notification');
  const notificationRef = db
    .collection(notificationCollection)
    .doc(cleanText(notificationId, deliveryRef.id));

  await notificationRef.set(
    {
      userId,
      type: notificationType,
      title,
      body,
      data,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  const badgeCount = Math.max(1, await unreadNotificationCount(userId));

  const tokens = userTokens(user);
  if (!tokens.length) {
    return 0;
  }

  try {
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, String(value)]),
      ),
      android: {
        priority: 'high',
        notification: {
          channelId: 'ccs_updates',
          sound: 'default',
          notificationCount: badgeCount,
        },
      },
      apns: {
        headers: {
          'apns-push-type': 'alert',
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title,
              body,
            },
            sound: 'default',
            badge: badgeCount,
          },
        },
      },
    });
    const invalidTokens = [];

    result.responses.forEach((response, index) => {
      const code = response.error && response.error.code;

      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        invalidTokens.push(tokens[index]);
      }
    });

    if (invalidTokens.length) {
      await userRef.update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }

    return result.successCount;
  } catch (error) {
    await deliveryRef.delete().catch(() => {});
    throw error;
  }
}

async function authenticatedUser(request) {
  const authorization = cleanText(request.headers.authorization);

  if (!authorization.startsWith('Bearer ')) {
    return null;
  }

  return admin.auth().verifyIdToken(authorization.slice('Bearer '.length));
}

function timestampMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : 0;
}

async function notificationCenterItems(userId) {
  const [notificationsSnapshot, newsSnapshot] = await Promise.all([
    db.collection('user_notifications').where('userId', '==', userId).get(),
    db.collection('project_news').get(),
  ]);

  const notifications = notificationsSnapshot.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      id: doc.id,
      title: cleanText(data.title, 'CCS'),
      body: cleanText(data.body),
      type: cleanText(data.type, 'notification'),
      read: data.read === true,
      createdAtMillis: timestampMillis(data.createdAt),
      projectNews: false,
    };
  });

  const news = newsSnapshot.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      id: `news_${doc.id}`,
      title: cleanText(data.title, 'Project news'),
      body: cleanText(data.body),
      type: 'project_news',
      read: true,
      createdAtMillis: timestampMillis(data.createdAt),
      projectNews: true,
    };
  });

  return [...notifications, ...news]
    .sort((first, second) => second.createdAtMillis - first.createdAtMillis)
    .slice(0, 80);
}

async function markNotificationsRead(userId, notificationIds) {
  const ids = Array.isArray(notificationIds)
    ? [...new Set(notificationIds.filter((id) => typeof id === 'string' && id.trim()))]
    : [];
  const batch = db.batch();
  let writes = 0;

  for (const id of ids.slice(0, 80)) {
    const ref = db.collection('user_notifications').doc(id);
    const snapshot = await ref.get();

    if (!snapshot.exists || snapshot.data().userId !== userId) {
      continue;
    }

    batch.set(
      ref,
      {
        read: true,
        readAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    writes++;
  }

  if (writes) {
    await batch.commit();
  }

  return writes;
}

async function requireStaff(userId) {
  const snapshot = await db.collection('users').doc(userId).get();
  const role = snapshot.exists ? snapshot.data().role : '';

  if (role !== 'admin' && role !== 'moderator') {
    throw new Error('Only staff users can send spot decisions.');
  }
}

async function notifyUsersAboutNewSpot({
  spotId,
  spot,
  deliveryKey,
  notificationType = 'new_spot',
}) {
  const ownerUid = spotNotificationOwnerUid(spot);
  const spotName = cleanText(spot.name, 'New car spot');
  const cityCountry = cleanText(spot.cityCountry);
  const locationSuffix = cityCountry ? ` in ${cityCountry}` : '';
  const isTemporary = notificationType === 'temporary_event' || spot.isTemporary === true;
  const title = isTemporary ? 'New CCS event' : 'New CCS spot';
  const body = isTemporary
    ? `${spotName} event was added${locationSuffix}.`
    : `${spotName}${locationSuffix}`;
  const usersSnapshot = await db.collection('users').get();

  return Promise.all(
    usersSnapshot.docs
      .filter((doc) => doc.id !== ownerUid)
      .map((doc) =>
        sendPushToUser({
          userId: doc.id,
          settingName: 'newSpotNotifications',
          deliveryKey,
          notificationId: `${notificationType}_${spotId}_${doc.id}`,
          title,
          body,
          data: { type: notificationType, spotId },
        }),
      ),
  );
}

async function handleSpotLike(userId, payload) {
  const likeId = cleanText(payload.likeId);
  const likeSnapshot = await db.collection('spot_likes').doc(likeId).get();
  const like = likeSnapshot.exists ? likeSnapshot.data() : null;

  if (!like || like.userId !== userId || like.targetType === 'comment' || like.commentId) {
    return [];
  }

  const spotId = cleanText(like.spotId);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data();
  const ownerUid = spotNotificationOwnerUid(spot);

  if (!ownerUid || ownerUid === userId) {
    return [];
  }

  return [
    await sendPushToUser({
      userId: ownerUid,
      settingName: 'likeNotifications',
      deliveryKey: `spot_like:${likeId}`,
      notificationId: cleanText(payload.notificationId, `spot_like_${likeId}`),
      title: 'New like',
      body: `@${cleanText(like.username, 'driver')} liked ${cleanText(spot.name, 'your spot')}.`,
      data: { type: 'spot_like', spotId, likeId },
    }),
  ];
}

async function handleSpotComment(userId, payload) {
  const reviewId = cleanText(payload.reviewId);
  const reviewSnapshot = await db.collection('spot_reviews').doc(reviewId).get();
  const review = reviewSnapshot.exists ? reviewSnapshot.data() : null;

  if (!review || review.userId !== userId || review.type !== 'comment') {
    return [];
  }

  const spotId = cleanText(review.spotId);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data();
  const ownerUid = spotNotificationOwnerUid(spot);

  if (!ownerUid || ownerUid === userId) {
    return [];
  }

  return [
    await sendPushToUser({
      userId: ownerUid,
      settingName: 'commentNotifications',
      deliveryKey: `spot_comment:${reviewId}`,
      notificationId: cleanText(payload.notificationId, `spot_comment_${reviewId}`),
      title: 'New comment',
      body: `@${cleanText(review.username, 'driver')}: ${shortText(review.comment)}`,
      data: { type: 'spot_comment', spotId, reviewId },
    }),
  ];
}

async function handleChatMessage(userId, payload) {
  const chatId = cleanText(payload.chatId);
  const messageId = cleanText(payload.messageId);
  const chatRef = db.collection('chats').doc(chatId);
  const [chatSnapshot, messageSnapshot] = await Promise.all([
    chatRef.get(),
    chatRef.collection('messages').doc(messageId).get(),
  ]);

  if (!chatSnapshot.exists || !messageSnapshot.exists) {
    return [];
  }

  const chat = chatSnapshot.data();
  const message = messageSnapshot.data();

  if (message.senderUid !== userId) {
    return [];
  }

  const senderUsername = cleanText(message.senderUsername, 'driver');
  const isGroup = chat.isGroup === true;
  const title = isGroup
    ? cleanText(chat.name, 'New group message')
    : `Message from @${senderUsername}`;
  const body = isGroup
    ? `@${senderUsername}: ${shortText(message.text)}`
    : shortText(message.text);
  const memberIds = Array.isArray(chat.memberIds) ? chat.memberIds : [];

  return Promise.all(
    memberIds
      .filter((memberId) => typeof memberId === 'string' && memberId !== userId)
      .map((memberId) =>
        sendPushToUser({
          userId: memberId,
          settingName: 'newMessageNotifications',
          deliveryKey: `chat_message:${chatId}:${messageId}`,
          title,
          body,
          data: { type: 'chat_message', chatId, messageId },
        }),
      ),
  );
}

async function handleFriendRequest(userId, payload) {
  const friendRequestId = cleanText(payload.friendRequestId);
  const requestSnapshot = await db.collection('friend_requests').doc(friendRequestId).get();

  if (!requestSnapshot.exists) {
    return [];
  }

  const request = requestSnapshot.data() || {};

  if (request.fromUid !== userId || request.status !== 'pending') {
    return [];
  }

  const toUid = cleanText(request.toUid);
  if (!toUid || toUid === userId) {
    return [];
  }

  const senderUsername = cleanText(request.fromUsername, 'driver');

  return [
    await sendPushToUser({
      userId: toUid,
      settingName: 'friendRequestNotifications',
      deliveryKey: `friend_request:${friendRequestId}`,
      notificationId: cleanText(payload.notificationId, `friend_request_${friendRequestId}`),
      title: 'New friend request',
      body: `@${senderUsername} sent you a friend request.`,
      data: {
        type: 'friend_request',
        friendRequestId,
        fromUid: userId,
        friendUsername: senderUsername,
      },
    }),
  ];
}

async function handleSpotDecision(userId, payload) {
  await requireStaff(userId);

  const spotId = cleanText(payload.spotId);
  const status = cleanText(payload.status);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists || (status !== 'approved' && status !== 'rejected')) {
    return [];
  }

  const spot = spotSnapshot.data();

  if (spot.status !== status || spot.reviewedByUid !== userId) {
    return [];
  }

  const approved = status === 'approved';
  const ownerUid = spotNotificationOwnerUid(spot);
  const results = [
    await sendPushToUser({
      userId: ownerUid,
      settingName: 'reviewNotifications',
      deliveryKey: `spot_decision:${spotId}:${status}`,
      notificationId: `spot_review_${spotId}_${status}_${ownerUid}`,
      title: approved ? 'Spot approved' : 'Spot rejected',
      body: approved
        ? `${cleanText(spot.name, 'Your spot')} is now visible in CCS.`
        : `${cleanText(spot.name, 'Your spot')} was not approved.`,
      data: {
        type: 'spot_review_update',
        spotId,
        status,
        rejectionReason: cleanText(payload.rejectionReason),
      },
    }),
  ];

  if (approved) {
    results.push(
      ...(await notifyUsersAboutNewSpot({
        spotId,
        spot,
        deliveryKey: `new_spot_approved:${spotId}`,
        notificationType: spot.isTemporary === true ? 'temporary_event' : 'new_spot',
      })),
    );
  }

  return results;
}

async function handleNewSpot(userId, payload) {
  const spotId = cleanText(payload.spotId);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data();

  if (spot.status !== 'approved' || spot.addedByUid !== userId) {
    return [];
  }

  await requireStaff(userId);

  return notifyUsersAboutNewSpot({
    spotId,
    spot,
    deliveryKey: `new_spot_created:${spotId}`,
    notificationType: 'new_spot',
  });
}

async function handleTemporaryEvent(userId, payload) {
  const spotId = cleanText(payload.spotId);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data();

  if (spot.status !== 'approved' || spot.addedByUid !== userId) {
    return [];
  }

  await requireStaff(userId);

  return notifyUsersAboutNewSpot({
    spotId,
    spot,
    deliveryKey: `temporary_event_created:${spotId}`,
    notificationType: 'temporary_event',
  });
}

async function handleTemporarySpotReminder(userId, payload) {
  await requireStaff(userId);

  const spotId = cleanText(payload.spotId);
  const spotSnapshot = await db.collection('spots').doc(spotId).get();
  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data() || {};
  const startsAtMillis = timestampToMillis(spot.startsAt);
  const nowMillis = Date.now();
  const reminderAtMillis = startsAtMillis - 5 * 60 * 60 * 1000;
  if (
    spot.isTemporary !== true ||
    spot.status !== 'approved' ||
    !startsAtMillis ||
    nowMillis < reminderAtMillis ||
    nowMillis >= startsAtMillis
  ) {
    return [];
  }

  let recipientUserIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
  if (!recipientUserIds.length) {
    const usersSnapshot = await db.collection('users').limit(500).get();
    recipientUserIds = usersSnapshot.docs
      .map((doc) => doc.id)
      .filter((recipientUserId) => recipientUserId !== userId);
  }

  const spotName = cleanText(spot.name, 'Temporary spot');
  const cityCountry = cleanText(spot.cityCountry);
  const locationSuffix = cityCountry ? ` in ${cityCountry}` : '';
  const title = 'Temporary spot starts in 5 hours';
  const body = `${spotName} starts in about 5 hours${locationSuffix}.`;
  const notificationBaseId = cleanText(
    payload.notificationId,
    `temporary_spot_reminder_${spotId}_${startsAtMillis}`,
  );

  return Promise.all(
    recipientUserIds.map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName: 'newSpotNotifications',
        deliveryKey: `temporary_spot_reminder:${spotId}:${startsAtMillis}`,
        notificationId: `${notificationBaseId}_${recipientUserId}`,
        title,
        body,
        data: {
          type: 'temporary_spot_today',
          preferenceKey: 'newSpotNotifications',
          spotId,
          spotName,
          cityCountry,
          startsAtMillis,
        },
      }),
    ),
  );
}

async function handleSpotPendingReview(userId, payload) {
  const spotId = cleanText(payload.spotId);
  const recipientUserIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists || !recipientUserIds.length) {
    return [];
  }

  const spot = spotSnapshot.data();

  if (spot.status !== 'pending' || spot.addedByUid !== userId) {
    return [];
  }

  const spotName = cleanText(spot.name, cleanText(payload.spotName, 'New spot'));
  const addedBy = cleanText(spot.addedBy, cleanText(payload.addedBy, 'driver'));

  return Promise.all(
    recipientUserIds.map(async (recipientUserId) => {
      const staffSnapshot = await db.collection('users').doc(recipientUserId).get();
      const staff = staffSnapshot.exists ? staffSnapshot.data() || {} : {};

      if (!staffSnapshot.exists || staff.deleted === true || staff.banned === true || !userIsStaff(staff)) {
        return 0;
      }

      return sendPushToUser({
        userId: recipientUserId,
        settingName: 'reviewNotifications',
        deliveryKey: `spot_pending_review:${spotId}:${recipientUserId}`,
        notificationId: `admin_${spotId}_review_${recipientUserId}`,
        notificationCollection: 'admin_notifications',
        title: 'Spot review updates',
        body: `${spotName} is waiting for review.`,
        data: {
          type: 'spot_pending_review',
          spotId,
          spotName,
          cityCountry: cleanText(spot.cityCountry, cleanText(payload.cityCountry)),
          addedBy,
          addedByUid: userId,
        },
      });
    }),
  );
}

async function handleFriendAtSpot(userId, payload) {
  const recipientUserIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
  const spotId = cleanText(payload.spotId);
  const spotName = cleanText(payload.spotName, 'a spot');
  const fallbackNotificationBucket = String(Math.floor(Date.now() / 1800000));
  const notificationBucket = payload.notificationBucket == null
    ? fallbackNotificationBucket
    : cleanText(String(payload.notificationBucket), fallbackNotificationBucket);

  if (!recipientUserIds.length || !spotId) {
    return [];
  }

  const senderSnapshot = await db.collection('users').doc(userId).get();
  const sender = senderSnapshot.exists ? senderSnapshot.data() || {} : {};
  const senderUsername = cleanText(sender.username, cleanText(payload.senderUsername, 'driver'));

  return Promise.all(
    recipientUserIds.map(async (recipientUserId) => {
      if (!(await friendshipAccepted(userId, recipientUserId))) {
        return 0;
      }

      return sendPushToUser({
        userId: recipientUserId,
        settingName: 'friendAtSpotNotifications',
        deliveryKey: `friend_at_spot:${userId}:${recipientUserId}:${spotId}:${notificationBucket}`,
        notificationId: `spot_${recipientUserId}_${userId}_${spotId}`,
        title: 'Live location',
        body: `@${senderUsername} is at ${spotName}.`,
        data: {
          type: 'friend_at_spot',
          spotId,
          spotName,
          friendUid: userId,
          friendUsername: senderUsername,
          lat: payload.lat ?? '',
          lng: payload.lng ?? '',
        },
      });
    }),
  );
}

async function handleFriendLiveSharing(userId, payload) {
  const recipientUserIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );

  if (!recipientUserIds.length) {
    return [];
  }

  const senderSnapshot = await db.collection('users').doc(userId).get();
  const sender = senderSnapshot.exists ? senderSnapshot.data() || {} : {};
  const senderUsername = cleanText(sender.username, cleanText(payload.senderUsername, 'driver'));
  const fallbackSessionKey = String(Math.floor(Date.now() / 1800000));
  const sessionKey = payload.sessionKey == null
    ? fallbackSessionKey
    : cleanText(String(payload.sessionKey), fallbackSessionKey);

  return Promise.all(
    recipientUserIds.map(async (recipientUserId) => {
      if (!(await friendshipAccepted(userId, recipientUserId))) {
        return 0;
      }

      return sendPushToUser({
        userId: recipientUserId,
        settingName: 'friendLiveShareNotifications',
        deliveryKey: `friend_live_sharing:${userId}:${recipientUserId}:${sessionKey}`,
        notificationId: `live_share_${recipientUserId}_${userId}_${sessionKey}`,
        title: 'Live location',
        body: `@${senderUsername} has been sharing live location for 10 minutes.`,
        data: {
          type: 'friend_live_sharing',
          friendUid: userId,
          friendUsername: senderUsername,
          lat: payload.lat ?? '',
          lng: payload.lng ?? '',
          sessionKey,
        },
      });
    }),
  );
}

async function communityRecipientIds(userId, payload, fallbackUserIds = []) {
  const explicitRecipients = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );

  if (explicitRecipients.length) {
    return explicitRecipients;
  }

  if (cleanText(payload.audience) === 'all_users') {
    const usersSnapshot = await db.collection('users').limit(500).get();
    return usersSnapshot.docs.map((doc) => doc.id).filter((id) => id !== userId);
  }

  return cleanStringArray(fallbackUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
}

function recipientNotificationId(payload, fallbackBase, recipientUserId) {
  const base = cleanText(payload.notificationId, fallbackBase);
  return base.endsWith(`_${recipientUserId}`) ? base : `${base}_${recipientUserId}`;
}

const GLOBAL_CHAT_DAILY_PUSH_COOLDOWN_MS = 24 * 60 * 60 * 1000;

async function claimGlobalChatDailyPushWindow(senderUid, messageId) {
  const globalRef = db.collection('push_throttles').doc('global_chat');
  const nowMillis = Date.now();

  return db.runTransaction(async (transaction) => {
    const globalSnapshot = await transaction.get(globalRef);
    const globalLastPushAtMillis = Number(
      globalSnapshot.exists ? globalSnapshot.data()?.lastPushAtMillis || 0 : 0,
    );
    const globalRemainingMs =
      globalLastPushAtMillis > 0
        ? GLOBAL_CHAT_DAILY_PUSH_COOLDOWN_MS - (nowMillis - globalLastPushAtMillis)
        : 0;

    if (globalRemainingMs > 0) {
      return {
        allowed: false,
        reason: 'global_24_hour_cooldown',
        remainingMs: globalRemainingMs,
      };
    }

    transaction.set(
      globalRef,
      {
        lastPushAtMillis: nowMillis,
        lastPushAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSenderUid: senderUid,
        lastMessageId: messageId,
      },
      { merge: true },
    );

    return { allowed: true, reason: 'allowed', remainingMs: 0 };
  });
}

async function globalChatReplyTarget(message, senderUid) {
  const replyToMessageId = cleanText(message.replyToMessageId);
  if (!replyToMessageId) {
    return null;
  }

  const originalSnapshot = await db
    .collection('global_chat')
    .doc(replyToMessageId)
    .get();
  if (!originalSnapshot.exists) {
    return null;
  }

  const recipientUserId = cleanText(originalSnapshot.data()?.userId);
  if (!recipientUserId || recipientUserId === senderUid) {
    return null;
  }

  return { recipientUserId, replyToMessageId };
}

async function handleGlobalChatMessage(userId, payload) {
  const messageId = cleanText(payload.messageId);
  if (!messageId) {
    return [];
  }

  const messageSnapshot = await db.collection('global_chat').doc(messageId).get();
  if (!messageSnapshot.exists) {
    return [];
  }

  const message = messageSnapshot.data() || {};
  const senderUid = cleanText(message.userId);
  if (senderUid !== userId) {
    return [];
  }

  const senderUsername = cleanText(
    message.username,
    cleanText(payload.senderUsername, 'driver'),
  );
  const messageText = shortText(
    message.text,
    cleanText(payload.messageText, message.photoUrl ? 'Photo' : 'New message'),
  );
  const title = 'Global chat';
  const body = `@${senderUsername}: ${messageText}`;

  const results = [];
  const replyTarget = await globalChatReplyTarget(message, senderUid);
  if (replyTarget) {
    try {
      results.push(
        await sendPushToUser({
          userId: replyTarget.recipientUserId,
          settingName: 'newMessageNotifications',
          deliveryKey: `global_chat_reply:${messageId}`,
          notificationId: recipientNotificationId(
            payload,
            `global_chat_${messageId}`,
            replyTarget.recipientUserId,
          ),
          title: 'Reply in Global chat',
          body: `@${senderUsername} replied: ${messageText}`,
          data: {
            type: 'global_chat_message',
            notificationKind: 'global_chat_reply',
            messageId,
            replyToMessageId: replyTarget.replyToMessageId,
            senderUid,
            senderUsername,
          },
        }),
      );
    } catch (error) {
      console.error('Global chat reply push failed:', error?.message || error);
    }
  }

  const recipientUserIds = (await communityRecipientIds(userId, payload)).filter(
    (recipientUserId) =>
      recipientUserId !== senderUid &&
      recipientUserId !== replyTarget?.recipientUserId,
  );
  if (!recipientUserIds.length) {
    return results;
  }

  const pushWindow = await claimGlobalChatDailyPushWindow(senderUid, messageId);
  if (!pushWindow.allowed) {
    console.log(
      `Global chat daily push suppressed: ${pushWindow.reason}; sender=${senderUid}; remainingMs=${Math.max(
        0,
        Math.ceil(pushWindow.remainingMs),
      )}`,
    );
    return results;
  }

  const broadcastResults = await Promise.all(
    recipientUserIds.map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName: 'newMessageNotifications',
        deliveryKey: `global_chat_message:${messageId}`,
        notificationId: recipientNotificationId(
          payload,
          `global_chat_${messageId}`,
          recipientUserId,
        ),
        title,
        body,
        data: {
          type: 'global_chat_message',
          messageId,
          senderUid,
          senderUsername,
        },
      }),
    ),
  );
  return [...results, ...broadcastResults];
}

async function handleForumReply(userId, payload) {
  const topicId = cleanText(payload.topicId);
  const messageId = cleanText(payload.messageId);
  const topicRef = db.collection('forum_topics').doc(topicId);
  const [topicSnapshot, replySnapshot] = await Promise.all([
    topicRef.get(),
    topicRef.collection('replies').doc(messageId).get(),
  ]);

  if (!topicSnapshot.exists || !replySnapshot.exists) {
    return [];
  }

  const topic = topicSnapshot.data() || {};
  const reply = replySnapshot.data() || {};

  if (cleanText(reply.userId) !== userId) {
    return [];
  }

  const authorId = cleanText(topic.authorId);
  const recipientUserIds = await communityRecipientIds(
    userId,
    payload,
    authorId ? [authorId] : [],
  );
  if (!recipientUserIds.length) {
    return [];
  }

  const senderUsername = cleanText(
    reply.username,
    cleanText(payload.senderUsername, 'driver'),
  );
  const topicTitle = cleanText(
    topic.title,
    cleanText(payload.topicTitle, 'Forum topic'),
  );
  const text = shortText(
    reply.text,
    cleanText(payload.messageText, reply.photoUrl ? 'Photo' : 'New reply'),
  );
  const title = `Forum: ${topicTitle}`;
  const body = `@${senderUsername}: ${text}`;

  return Promise.all(
    recipientUserIds.map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName: 'commentNotifications',
        deliveryKey: `forum_reply:${topicId}:${messageId}`,
        notificationId: recipientNotificationId(
          payload,
          `forum_${topicId}_${messageId}`,
          recipientUserId,
        ),
        title,
        body,
        data: {
          type: 'forum_reply',
          topicId,
          topicTitle,
          messageId,
          senderUid: userId,
          senderUsername,
        },
      }),
    ),
  );
}

async function configuredCommunityModeratorIds() {
  try {
    const snapshot = await db.collection('app_config').doc('global_chat').get();
    const data = snapshot.exists ? snapshot.data() || {} : {};
    return new Set([
      ...cleanStringArray(data.moderatorIds),
      ...cleanStringArray(data.globalModeratorIds),
    ]);
  } catch (error) {
    console.warn('Community moderator config lookup skipped:', error?.message || error);
    return new Set();
  }
}

async function verifiedCommunityModeratorIds(userId, payload) {
  const requestedIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
  if (!requestedIds.length) {
    return [];
  }

  const configuredIds = await configuredCommunityModeratorIds();
  const snapshots = await Promise.all(
    requestedIds.map((recipientUserId) => db.collection('users').doc(recipientUserId).get()),
  );

  return snapshots
    .filter((snapshot) => {
      if (!snapshot.exists) {
        return false;
      }

      const recipient = snapshot.data() || {};
      return (
        recipient.deleted !== true &&
        !userHasActiveBan(recipient) &&
        (userIsStaff(recipient) ||
          recipient.globalChatModerator === true ||
          recipient.globalModerator === true ||
          configuredIds.has(snapshot.id))
      );
    })
    .map((snapshot) => snapshot.id);
}

async function sendCommunityModeratorPush({
  userId,
  payload,
  recipientUserIds,
  deliveryKey,
  fallbackNotificationId,
  fallbackTitle,
  fallbackBody,
  data,
}) {
  const title = fallbackTitle;
  const body = fallbackBody;

  return Promise.all(
    recipientUserIds.map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName: 'reviewNotifications',
        deliveryKey,
        notificationId: recipientNotificationId(
          payload,
          fallbackNotificationId,
          recipientUserId,
        ),
        notificationCollection: 'admin_notifications',
        title,
        body,
        data,
      }),
    ),
  );
}

async function handleGlobalChatAdmin(userId, payload) {
  const messageId = cleanText(payload.messageId);
  const messageSnapshot = await db.collection('global_chat').doc(messageId).get();
  if (!messageSnapshot.exists) {
    return [];
  }

  const message = messageSnapshot.data() || {};
  if (cleanText(message.userId) !== userId) {
    return [];
  }

  const recipientUserIds = await verifiedCommunityModeratorIds(userId, payload);
  if (!recipientUserIds.length) {
    return [];
  }

  const senderUsername = cleanText(message.username, 'driver');
  const messageText = shortText(
    message.text,
    message.photoUrl ? 'Photo' : 'New message',
  );

  return sendCommunityModeratorPush({
    userId,
    payload,
    recipientUserIds,
    deliveryKey: `global_chat_admin:${messageId}`,
    fallbackNotificationId: `global_chat_admin_${messageId}`,
    fallbackTitle: 'New global chat message',
    fallbackBody: `@${senderUsername}: ${messageText}`,
    data: {
      type: 'global_chat_admin',
      messageId,
      senderUid: userId,
      senderUsername,
    },
  });
}

async function handleForumReplyAdmin(userId, payload) {
  const topicId = cleanText(payload.topicId);
  const messageId = cleanText(payload.messageId);
  const topicRef = db.collection('forum_topics').doc(topicId);
  const [topicSnapshot, replySnapshot] = await Promise.all([
    topicRef.get(),
    topicRef.collection('replies').doc(messageId).get(),
  ]);

  if (!topicSnapshot.exists || !replySnapshot.exists) {
    return [];
  }

  const topic = topicSnapshot.data() || {};
  const reply = replySnapshot.data() || {};
  if (cleanText(reply.userId) !== userId) {
    return [];
  }

  const recipientUserIds = await verifiedCommunityModeratorIds(userId, payload);
  if (!recipientUserIds.length) {
    return [];
  }

  const senderUsername = cleanText(reply.username, 'driver');
  const topicTitle = cleanText(topic.title, cleanText(payload.topicTitle, 'Forum topic'));
  const messageText = shortText(
    reply.text,
    reply.photoUrl ? 'Photo' : 'New reply',
  );

  return sendCommunityModeratorPush({
    userId,
    payload,
    recipientUserIds,
    deliveryKey: `forum_reply_admin:${topicId}:${messageId}`,
    fallbackNotificationId: `forum_reply_admin_${topicId}_${messageId}`,
    fallbackTitle: 'New forum reply',
    fallbackBody: `@${senderUsername}: ${messageText}`,
    data: {
      type: 'forum_reply_admin',
      topicId,
      topicTitle,
      messageId,
      senderUid: userId,
      senderUsername,
    },
  });
}

export default async function handler(request, response) {
  try {
    const user = await authenticatedUser(request);

    if (!user) {
      response.status(401).json({ status: 'error', message: 'Sign in first.' });
      return;
    }

    if (request.method === 'GET') {
      response.status(200).json({
        status: 'ok',
        notifications: await notificationCenterItems(user.uid),
      });
      return;
    }

    if (request.method === 'PATCH') {
      response.status(200).json({
        status: 'ok',
        updated: await markNotificationsRead(
          user.uid,
          request.body && request.body.notificationIds,
        ),
      });
      return;
    }

    if (request.method !== 'POST') {
      response.status(405).json({ status: 'error', message: 'Method not allowed.' });
      return;
    }

    const type = cleanText(request.body && request.body.type);
    const handlers = {
      spot_like: handleSpotLike,
      spot_comment: handleSpotComment,
      chat_message: handleChatMessage,
      friend_request: handleFriendRequest,
      spot_decision: handleSpotDecision,
      spot_pending_review: handleSpotPendingReview,
      new_spot: handleNewSpot,
      temporary_event: handleTemporaryEvent,
      temporary_spot_today: handleTemporarySpotReminder,
      friend_at_spot: handleFriendAtSpot,
      friend_live_sharing: handleFriendLiveSharing,
      global_chat_message: handleGlobalChatMessage,
      global_chat_admin: handleGlobalChatAdmin,
      forum_reply: handleForumReply,
      forum_reply_admin: handleForumReplyAdmin,
    };
    const handler = handlers[type];

    if (!handler) {
      response.status(400).json({ status: 'error', message: 'Unsupported notification type.' });
      return;
    }

    const results = await handler(user.uid, request.body || {});
    const delivered = results.reduce((total, count) => total + Number(count || 0), 0);

    response.status(200).json({
      status: 'ok',
      processed: results.length,
      delivered,
    });
  } catch (error) {
    response.status(500).json({
      status: 'error',
      message: String(error && error.message ? error.message : error),
    });
  }
}
