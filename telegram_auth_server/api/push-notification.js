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
  commentNotifications: false,
  newSpotNotifications: true,
  newMessageNotifications: true,
  friendRequestNotifications: true,
};

function cleanText(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function shortText(value, fallback = '', maxLength = 140) {
  const text = cleanText(value, fallback);
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}...`;
}

function settingEnabled(user, settingName) {
  const settings = user.settings || {};
  const fallback = defaultNotificationSettings[settingName] === true;
  return typeof settings[settingName] === 'boolean'
    ? settings[settingName]
    : fallback;
}

function userTokens(user) {
  if (!Array.isArray(user.fcmTokens)) {
    return [];
  }

  return [...new Set(user.fcmTokens.filter((token) => typeof token === 'string' && token.trim()))];
}

function deliveryId(deliveryKey, userId) {
  return crypto
    .createHash('sha256')
    .update(`${deliveryKey}|${userId}`)
    .digest('hex');
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
  const snapshot = await db
    .collection('user_notifications')
    .where('userId', '==', userId)
    .where('read', '==', false)
    .get();

  return snapshot.size;
}

async function sendPushToUser({
  userId,
  settingName,
  deliveryKey,
  notificationId,
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

  if (user.deleted === true || !settingEnabled(user, settingName)) {
    return 0;
  }

  const deliveryRef = await claimDelivery(deliveryKey, userId);
  if (!deliveryRef) {
    return 0;
  }

  const notificationType = cleanText(data.type, 'notification');
  const notificationRef = db
    .collection('user_notifications')
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
          'apns-priority': '10',
        },
        payload: {
          aps: {
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

async function notifyUsersAboutNewSpot({ spotId, spot, deliveryKey }) {
  const ownerUid = cleanText(spot.addedByUid);
  const spotName = cleanText(spot.name, 'New car spot');
  const cityCountry = cleanText(spot.cityCountry);
  const locationSuffix = cityCountry ? ` in ${cityCountry}` : '';
  const usersSnapshot = await db.collection('users').get();

  return Promise.all(
    usersSnapshot.docs
      .filter((doc) => doc.id !== ownerUid)
      .map((doc) =>
        sendPushToUser({
          userId: doc.id,
          settingName: 'newSpotNotifications',
          deliveryKey,
          title: 'New CCS spot',
          body: `${spotName}${locationSuffix}`,
          data: { type: 'new_spot', spotId },
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
  const ownerUid = cleanText(spot.addedByUid);

  if (!ownerUid || ownerUid === userId) {
    return [];
  }

  return [
    await sendPushToUser({
      userId: ownerUid,
      settingName: 'likeNotifications',
      deliveryKey: `spot_like:${likeId}`,
      title: 'New like',
      body: `@${cleanText(like.username, 'driver')} liked ${cleanText(spot.name, 'your spot')}.`,
      data: { type: 'spot_like', spotId },
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
  const ownerUid = cleanText(spot.addedByUid);

  if (!ownerUid || ownerUid === userId) {
    return [];
  }

  return [
    await sendPushToUser({
      userId: ownerUid,
      settingName: 'commentNotifications',
      deliveryKey: `spot_comment:${reviewId}`,
      title: 'New comment',
      body: `@${cleanText(review.username, 'driver')}: ${shortText(review.comment)}`,
      data: { type: 'spot_comment', spotId },
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
      notificationId: `friend_request_${friendRequestId}`,
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
  const results = [
    await sendPushToUser({
      userId: cleanText(spot.addedByUid),
      settingName: 'reviewNotifications',
      deliveryKey: `spot_decision:${spotId}:${status}`,
      title: approved ? 'Spot approved' : 'Spot rejected',
      body: approved
        ? `${cleanText(spot.name, 'Your spot')} is now visible in CCS.`
        : `${cleanText(spot.name, 'Your spot')} was not approved.`,
      data: { type: 'spot_review_update', spotId, status },
    }),
  ];

  if (approved) {
    results.push(
      ...(await notifyUsersAboutNewSpot({
        spotId,
        spot,
        deliveryKey: `new_spot_approved:${spotId}`,
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
      new_spot: handleNewSpot,
    };
    const handler = handlers[type];

    if (!handler) {
      response.status(400).json({ status: 'error', message: 'Unsupported notification type.' });
      return;
    }

    const results = await handler(user.uid, request.body || {});
    const delivered = results.reduce((total, count) => total + Number(count || 0), 0);

    response.status(200).json({ status: 'ok', delivered });
  } catch (error) {
    response.status(500).json({
      status: 'error',
      message: String(error && error.message ? error.message : error),
    });
  }
}
