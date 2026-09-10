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

function countryFromCityCountry(value) {
  const parts = cleanText(value)
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
  return parts.length ? parts[parts.length - 1] : '';
}

const supportedCountryIsoCodes = [
  'AL', 'AM', 'AU', 'AT', 'AZ', 'BY', 'BE', 'BA', 'BR', 'BG', 'CA', 'CN',
  'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'GE', 'DE', 'GR', 'HU', 'IS',
  'IN', 'IE', 'IT', 'JP', 'LV', 'LT', 'LU', 'MT', 'MX', 'MD', 'ME', 'NL',
  'NZ', 'MK', 'NO', 'PL', 'PT', 'RO', 'RU', 'RS', 'SK', 'SI', 'KR', 'ES',
  'SE', 'CH', 'TR', 'UA', 'AE', 'GB', 'US',
];

const countryAliasesToIso = (() => {
  const aliases = new Map();
  for (const locale of ['en', 'ru', 'lv']) {
    const displayNames = new Intl.DisplayNames([locale], { type: 'region' });
    for (const isoCode of supportedCountryIsoCodes) {
      const name = displayNames.of(isoCode);
      if (name) {
        aliases.set(name.trim().toLocaleLowerCase('en-US'), isoCode);
      }
      aliases.set(isoCode.toLocaleLowerCase('en-US'), isoCode);
    }
  }
  aliases.set('uk', 'GB');
  aliases.set('great britain', 'GB');
  aliases.set('usa', 'US');
  aliases.set('сша', 'US');
  aliases.set('asv', 'US');
  aliases.set('uae', 'AE');
  aliases.set('оаэ', 'AE');
  aliases.set('aae', 'AE');
  aliases.set('czech republic', 'CZ');
  return aliases;
})();

function countryKey(value) {
  const normalized = cleanText(value).toLocaleLowerCase('en-US');
  return countryAliasesToIso.get(normalized) || normalized;
}

function userAllowsSpotCountry(user, spotCountry) {
  const targetCountry = countryKey(spotCountry);
  if (!targetCountry) {
    return true;
  }

  if (cleanText(user.role) === 'moderator') {
    return cleanStringArray(user.moderatorCountryCodes)
      .map(countryKey)
      .includes(targetCountry);
  }

  const selectedCountries = cleanStringArray(user.spotCountryFilters)
    .map(countryKey)
    .filter(Boolean);
  if (selectedCountries.length) {
    return selectedCountries.includes(targetCountry);
  }

  // Existing users who have not opened the new filter yet default to the
  // country already stored on their profile.
  const profileCountry = countryKey(user.country);
  return profileCountry ? profileCountry === targetCountry : true;
}

function userMatchesCommunityCountry(user, communityCountry) {
  const targetCountry = countryKey(communityCountry);
  if (!targetCountry) return true;
  // Existing profiles without a country predate regional communities and
  // belong to the original Latvian community.
  const profileCountry = countryKey(user.country) || 'LV';
  return profileCountry === targetCountry;
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

function userCanModerateSpotCountry(user = {}, spotCountryCode = '') {
  const role = cleanText(user.role);
  if (role === 'admin') {
    return true;
  }
  if (role !== 'moderator') {
    return false;
  }

  const countryCode = countryKey(spotCountryCode);
  if (!countryCode) {
    return false;
  }
  return cleanStringArray(user.moderatorCountryCodes)
    .map(countryKey)
    .includes(countryCode);
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

async function sendPushToUser({
  userId,
  settingName,
  spotCountry = '',
  communityCountry = '',
  deliveryKey,
  notificationId,
  notificationCollection = 'user_notifications',
  pushEnabled = true,
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
    !settingEnabled(user, settingName) ||
    !userMatchesCommunityCountry(user, communityCountry) ||
    !userAllowsSpotCountry(user, spotCountry)
  ) {
    return 0;
  }

  if (notificationCollection === 'admin_notifications' &&
      !userCanModerateCommunityCountry(user, data.countryCode)) return 0;

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
  // Suppressed publications still appear in the notification bell.
  if (!pushEnabled) return 0;

  // Notification history can contain legacy duplicates and items hidden only
  // on a particular device. It is not a reliable source for the OS badge.
  const badgeCount = 1;

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

const PERMANENT_SPOT_PUSH_COOLDOWN_MS = 5 * 60 * 60 * 1000;

async function spotPublicationPushAllowed(spotId, isTemporary) {
  if (isTemporary) return true;
  const eventRef = db.collection('push_dispatches').doc(deliveryId(`spot_publication:${spotId}`, 'push_policy'));
  const windowRef = db.collection('push_throttles').doc('permanent_spot_publications');
  return db.runTransaction(async transaction => {
    const [event, window] = await Promise.all([
      transaction.get(eventRef), transaction.get(windowRef),
    ]);
    // Keep the original decision on retries. A suppressed publication must not
    // send a delayed push when it is retried after the cooldown has expired.
    if (event.exists) return event.data().pushAllowed === true;
    const nowMillis = Date.now();
    const lastPushAtMillis = Number(window.data()?.lastPushAtMillis || 0);
    const allowed = !window.exists || nowMillis - lastPushAtMillis >= PERMANENT_SPOT_PUSH_COOLDOWN_MS;
    transaction.set(eventRef, { spotId, pushAllowed: allowed, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    if (allowed) {
      transaction.set(windowRef, {
        lastPushAtMillis: nowMillis, lastSpotId: spotId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return allowed;
  });
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
  const spotCountry = countryFromCityCountry(cityCountry);
  const locationSuffix = cityCountry ? ` in ${cityCountry}` : '';
  const isTemporary = spot.isTemporary === true;
  notificationType = isTemporary ? 'temporary_event' : 'new_spot';
  const pushEnabled = await spotPublicationPushAllowed(spotId, isTemporary);
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
          spotCountry,
          // Creation, approval and both backend hosts share the same claim.
          deliveryKey: `spot_publication:${spotId}`,
          pushEnabled,
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

function mentionedUsernames(text) {
  return [...new Set([...String(text || '').matchAll(/(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{2,30})(?![A-Za-z0-9_])/g)]
    .map(match => match[1].toLowerCase()))];
}

async function handleMentions(userId, type, payload) {
  const validId = value => typeof value === 'string' && value.length > 0 && !value.includes('/');
  let source, text, context, allowedIds = null, key, notificationBase;
  let forumPushRecipients = null;
  if (type === 'chat_message' && validId(payload.chatId) && validId(payload.messageId)) {
    const chatRef = db.collection('chats').doc(payload.chatId);
    const [chatDoc, messageDoc] = await Promise.all([chatRef.get(), chatRef.collection('messages').doc(payload.messageId).get()]);
    const chat = chatDoc.data();
    source = messageDoc.data();
    allowedIds = cleanStringArray(chat?.memberIds);
    if (!chatDoc.exists || !messageDoc.exists || source.senderUid !== userId || !allowedIds.includes(userId)) return {recipients: [], results: []};
    text = source.text;
    context = {type, chatId: payload.chatId, messageId: payload.messageId};
    key = `chat:${payload.chatId}:${payload.messageId}`;
    notificationBase = `chat_${payload.chatId}_${payload.messageId}`;
  } else if (type === 'global_chat_message' && validId(payload.messageId)) {
    source = (await db.collection('global_chat').doc(payload.messageId).get()).data();
    if (!source || source.userId !== userId) return {recipients: [], results: []};
    text = source.text;
    context = {type, messageId: payload.messageId, countryCode: countryKey(source.countryCode) || 'LV'};
    key = `global:${payload.messageId}`;
    notificationBase = `global_chat_${payload.messageId}`;
  } else if (type === 'forum_reply' && validId(payload.topicId) && validId(payload.messageId)) {
    const ref = db.collection('forum_topics').doc(payload.topicId);
    const [topicDoc, replyDoc] = await Promise.all([ref.get(), ref.collection('replies').doc(payload.messageId).get()]);
    source = replyDoc.data();
    if (!topicDoc.exists || !source || source.userId !== userId || topicDoc.data().status !== 'approved') return {recipients: [], results: []};
    forumPushRecipients = new Set([cleanText(topicDoc.data().authorId)]);
    if (validId(source.replyToMessageId)) {
      const original = await ref.collection('replies').doc(source.replyToMessageId).get();
      forumPushRecipients.add(cleanText(original.data()?.userId));
    }
    text = source.text;
    context = {type, topicId: payload.topicId, messageId: payload.messageId, topicTitle: cleanText(topicDoc.data().title, 'Forum')};
    key = `forum:${payload.topicId}:${payload.messageId}`;
    notificationBase = `forum_${payload.topicId}_${payload.messageId}`;
  } else if (type === 'spot_comment' && validId(payload.reviewId)) {
    source = (await db.collection('spot_reviews').doc(payload.reviewId).get()).data();
    if (!source || source.userId !== userId || source.type !== 'comment' || !validId(source.spotId)) return {recipients: [], results: []};
    const spot = (await db.collection('spots').doc(source.spotId).get()).data();
    if (!spot || spot.status !== 'approved') return {recipients: [], results: []};
    text = source.comment;
    context = {type, spotId: source.spotId, reviewId: payload.reviewId, spotName: cleanText(spot.name)};
    key = `comment:${payload.reviewId}`;
    notificationBase = `spot_comment_${payload.reviewId}`;
  } else return {recipients: [], results: []};

  const handles = mentionedUsernames(text);
  if (!handles.length) return {recipients: [], results: []};
  const senderDoc = await db.collection('users').doc(userId).get();
  const sender = senderDoc.data();
  if (!sender || sender.deleted === true || userHasActiveBan(sender)) return {recipients: [], results: []};
  // Query canonical handles first; legacy accounts may lack usernameKey.
  // Fall back only for unresolved handles, comparing exact current usernames.
  const found = new Map();
  for (let start = 0; start < handles.length; start += 30) {
    const snapshot = await db.collection('users').where('usernameKey', 'in', handles.slice(start, start + 30)).get();
    for (const doc of snapshot.docs) {
      const handle = cleanText(doc.data().username).replace(/^@/, '').toLowerCase();
      if (handles.includes(handle)) found.set(handle, doc.id);
    }
  }
  if (handles.some(handle => !found.has(handle))) {
    const directory = await db.collection('users').select('username').get();
    for (const doc of directory.docs) {
      const handle = cleanText(doc.data().username).replace(/^@/, '').toLowerCase();
      if (handles.includes(handle) && !found.has(handle)) found.set(handle, doc.id);
    }
  }
  const recipients = [...new Set(found.values())].filter(uid => uid !== userId && (allowedIds === null || allowedIds.includes(uid)));
  const senderUsername = cleanText(sender.username, 'driver');
  const results = await Promise.all(recipients.map(uid => sendPushToUser({
    userId: uid,
    settingName: type === 'spot_comment' || type === 'forum_reply' ? 'commentNotifications' : 'newMessageNotifications',
    pushEnabled: forumPushRecipients === null || forumPushRecipients.has(uid),
    deliveryKey: type === 'forum_reply' ? `forum_reply:${payload.topicId}:${payload.messageId}` : `mention:${key}`,
    notificationId: `${notificationBase}_${uid}`,
    title: 'You were mentioned',
    body: `@${senderUsername} mentioned you: ${shortText(text)}`,
    data: {...context, notificationKind: 'mention', senderUid: userId, actorUserId: userId, senderUsername},
  })));
  return {recipients, results};
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

  if (!ownerUid || ownerUid === userId || payload._mentionRecipientIds?.includes(ownerUid)) {
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
      .filter((memberId) => typeof memberId === 'string' && memberId !== userId && !payload._mentionRecipientIds?.includes(memberId))
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

async function handleGroupJoinRequest(userId, payload) {
  const chatId = cleanText(payload.chatId);
  if (!chatId || chatId.includes('/')) return [];
  const chatRef = db.collection('chats').doc(chatId);
  const [chatDoc, requestDoc] = await Promise.all([chatRef.get(), chatRef.collection('join_requests').doc(userId).get()]);
  if (!chatDoc.exists || !requestDoc.exists || requestDoc.data().status !== 'pending') return [];
  const chat = chatDoc.data();
  if (chat.isGroup !== true) return [];
  const owner = chat.ownerUid || (chat.memberIds || [])[0];
  if (!owner || owner === userId) return [];
  return [await sendPushToUser({
    userId: owner, settingName: 'friendRequestNotifications',
    deliveryKey: `group_join_request:${chatId}:${userId}`,
    notificationId: `group_request_${chatId}_${userId}`,
    title: 'Group join request',
    body: `@${cleanText(requestDoc.data().username, 'driver')} wants to join ${cleanText(chat.name, 'your group')}.`,
    data: { type: 'group_join_request', chatId, actorUserId: userId },
  })];
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

// Claim the whole reminder before scanning users, not just each recipient after
// the scan. Shared by all staff devices, including older client builds.
async function runTemporaryReminderOnce(eventKey, dispatch) {
  const ref = db.collection('push_dispatches').doc(deliveryId(eventKey, 'event'));
  const token = crypto.randomUUID();
  const claim = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() || {};
    if (data.status === 'complete') return 'complete';
    if (Number(data.retryAfterMillis || 0) > Date.now()) return 'busy';
    transaction.set(ref, {
      eventKey, token, status: 'processing',
      retryAfterMillis: Date.now() + 5 * 60 * 1000,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return 'claimed';
  });
  if (claim === 'complete') return [];
  // Non-success lets the app retry later if the original process crashes.
  if (claim === 'busy') throw new Error('Reminder dispatch in progress; retry later.');
  // On failure retain the cooldown. Existing per-user delivery keys protect
  // completed recipients when a later request retries the interrupted dispatch.
  const results = await dispatch();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.token === token) {
      transaction.update(ref, {
        status: 'complete', updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
  return results;
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

  return runTemporaryReminderOnce(
    `temporary_spot_reminder:${spotId}:${startsAtMillis}`,
    async () => {
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
      const spotCountry = countryFromCityCountry(cityCountry);
      const locationSuffix = cityCountry ? ` in ${cityCountry}` : '';
      const title = 'Temporary spot starts in 5 hours';
      const body = `${spotName} starts in about 5 hours${locationSuffix}.`;
      const notificationBaseId = `temporary_spot_reminder_${spotId}_${startsAtMillis}`;

      const outcomes = await Promise.allSettled(
        recipientUserIds.map((recipientUserId) =>
          sendPushToUser({
            userId: recipientUserId,
            settingName: 'newSpotNotifications',
            spotCountry,
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
      const failure = outcomes.find((outcome) => outcome.status === 'rejected');
      if (failure) throw failure.reason;
      return outcomes.map((outcome) => outcome.value);
    },
  );
}

async function handleSpotPendingReview(userId, payload) {
  const spotId = cleanText(payload.spotId);
  if (!spotId) return [];
  const spotSnapshot = await db.collection('spots').doc(spotId).get();

  if (!spotSnapshot.exists) {
    return [];
  }

  const spot = spotSnapshot.data();

  const isEdited = spot.status === 'edited' && spot.editReviewStatus === 'pending';
  if (
    spot.addedByUid !== userId ||
    (spot.status !== 'pending' && !isEdited) ||
    (payload.reviewKind === 'edited' && !isEdited) ||
    (isEdited && spot.editedByUid !== userId)
  ) {
    return [];
  }

  // Use the saved edit timestamp, never a caller-provided notification ID.
  // Counters can update updatedAt independently, so editedAt identifies review.
  const editRevision = isEdited ? timestampToMillis(spot.editedAt) : 0;
  if (isEdited && !editRevision) return [];
  const recipientUserIds = isEdited
    ? await activeStaffUserIdsExcept(userId)
    : cleanStringArray(payload.recipientUserIds).filter(id => id !== userId);

  const spotName = cleanText(spot.name, cleanText(payload.spotName, 'New spot'));
  const addedBy = cleanText(spot.addedBy, cleanText(payload.addedBy, 'driver'));
  const cityCountry = cleanText(spot.cityCountry, cleanText(payload.cityCountry));
  const spotCountryCode = countryKey(
    cleanText(spot.countryCode),
  );

  return Promise.all(
    recipientUserIds.map(async (recipientUserId) => {
      const staffSnapshot = await db.collection('users').doc(recipientUserId).get();
      const staff = staffSnapshot.exists ? staffSnapshot.data() || {} : {};

      if (
        !staffSnapshot.exists ||
        staff.deleted === true ||
        userHasActiveBan(staff) ||
        !userCanModerateSpotCountry(staff, spotCountryCode)
      ) {
        return 0;
      }

      return sendPushToUser({
        userId: recipientUserId,
        settingName: 'reviewNotifications',
        deliveryKey: isEdited
          ? `spot_edit_review:${spotId}:${editRevision}:${recipientUserId}`
          : `spot_pending_review:${spotId}:${recipientUserId}`,
        notificationId: isEdited
          ? `admin_${spotId}_edit_${editRevision}_${recipientUserId}`
          : `admin_${spotId}_review_${recipientUserId}`,
        notificationCollection: 'admin_notifications',
        title: isEdited ? 'Spot edited — approval required' : 'Spot review updates',
        body: isEdited
          ? `@${addedBy} edited ${spotName}. Please review and approve it again.`
          : `${spotName} is waiting for review.`,
        data: {
          type: 'spot_pending_review',
          reviewKind: isEdited ? 'edited' : 'new',
          status: spot.status,
          editRevision,
          preferenceKey: 'reviewNotifications',
          spotId,
          spotName,
          cityCountry,
          countryCode: spotCountryCode,
          addedBy,
          addedByUid: userId,
        },
      });
    }),
  );
}

const SPOT_PRESENCE_RADIUS_METERS = 200;
const SPOT_PRESENCE_DWELL_MS = 5 * 60 * 1000;
const SPOT_PRESENCE_MAX_SAMPLE_GAP_MS = 150 * 1000;

function presenceCoordinates(data = {}) {
  const lat = data?.coordinates?.latitude ?? data?.lat;
  const lng = data?.coordinates?.longitude ?? data?.lng;
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? {lat, lng} : null;
}
function presenceDistance(a, b) {
  const radians = Math.PI / 180;
  const dLat = (b.lat - a.lat) * radians;
  const dLng = (b.lng - a.lng) * radians;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * radians) * Math.cos(b.lat * radians) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}

function advanceSpotPresence(previous, live, spots, now) {
  const position = presenceCoordinates(live);
  const sampleAt = timestampToMillis(live?.updatedAt);
  const session = timestampToMillis(live?.expiresAt);
  const empty = {session, sampleAt, visits: {}};
  if (!live || !position || session <= now || sampleAt <= 0 || sampleAt > now || now - sampleAt > SPOT_PRESENCE_MAX_SAMPLE_GAP_MS) return {state: empty, ready: []};
  // Repeated calls for the same stored GPS sample do not advance dwell time.
  if (previous.session === session && sampleAt <= (previous.sampleAt || 0)) return {state: previous, ready: []};
  const continuous = previous.session === session && sampleAt - (previous.sampleAt || 0) <= SPOT_PRESENCE_MAX_SAMPLE_GAP_MS;
  const visits = {};
  const ready = [];
  for (const spot of spots) {
    const coordinates = presenceCoordinates(spot);
    if (spot.status !== 'approved' || !coordinates || (spot.isTemporary === true && timestampToMillis(spot.expiresAt) <= now)) continue;
    if (presenceDistance(position, coordinates) > SPOT_PRESENCE_RADIUS_METERS) continue;
    const prior = continuous ? previous.visits?.[spot.id] : null;
    const visit = prior || {enteredAt: now, notified: false};
    visits[spot.id] = visit;
    if (!visit.notified && now - visit.enteredAt >= SPOT_PRESENCE_DWELL_MS) ready.push({spot, enteredAt: visit.enteredAt});
  }
  return {state: {session, sampleAt, visits}, ready};
}

// Reuse public spot metadata between heartbeats on a warm backend instance.
// Expiration is still checked per observation; rejected/deleted spots disappear
// on the next refresh, and each ready notification re-reads its spot below.
let presenceSpotsCache = null;
let presenceSpotsCacheUntil = 0;
async function presenceSpots() {
  if (presenceSpotsCache && Date.now() < presenceSpotsCacheUntil) return presenceSpotsCache;
  const snapshot = await db.collection('spots').where('status', '==', 'approved')
    .select('name', 'coordinates', 'lat', 'lng', 'status', 'isTemporary', 'expiresAt').get();
  presenceSpotsCache = snapshot.docs.map(doc => ({...doc.data(), id: doc.id}));
  presenceSpotsCacheUntil = Date.now() + 60 * 1000;
  return presenceSpotsCache;
}

async function handleFriendAtSpot(userId, payload) {
  // Never trust caller-supplied coordinates, recipients, spot names or timers.
  const senderDoc = await db.collection('users').doc(userId).get();
  const sender = senderDoc.data() || {};
  if (!senderDoc.exists || sender.deleted === true || userHasActiveBan(sender)) return [];
  const spots = await presenceSpots();
  const stateRef = db.collection('spot_presence').doc(userId);
  const liveRef = db.collection('live_locations').doc(userId);
  const observation = await db.runTransaction(async tx => {
    const [stateDoc, liveDoc] = await Promise.all([tx.get(stateRef), tx.get(liveRef)]);
    const live = liveDoc.data();
    const advanced = advanceSpotPresence(stateDoc.data() || {}, live, spots, Date.now());
    tx.set(stateRef, advanced.state);
    return {...advanced, live};
  });
  if (!observation.ready.length) return [];
  const friendships = await db.collection('friendships').where('userIds', 'array-contains', userId).get();
  const friends = [...new Set(friendships.docs.flatMap(doc => cleanStringArray(doc.data().userIds)))]
    .filter(uid => uid !== userId);
  const results = [];
  for (const {spot, enteredAt} of observation.ready) {
    const [currentSpotDoc, currentLiveDoc] = await Promise.all([
      db.collection('spots').doc(spot.id).get(), liveRef.get(),
    ]);
    const currentSpot = currentSpotDoc.data();
    const currentLive = currentLiveDoc.data();
    const livePosition = presenceCoordinates(currentLive);
    const spotPosition = presenceCoordinates(currentSpot);
    if (!currentSpotDoc.exists || currentSpot.status !== 'approved' || !currentLiveDoc.exists || !livePosition || !spotPosition ||
        timestampToMillis(currentLive.expiresAt) !== observation.state.session || timestampToMillis(currentLive.expiresAt) <= Date.now() ||
        Date.now() - timestampToMillis(currentLive.updatedAt) > SPOT_PRESENCE_MAX_SAMPLE_GAP_MS ||
        (currentSpot.isTemporary === true && timestampToMillis(currentSpot.expiresAt) <= Date.now()) ||
        presenceDistance(livePosition, spotPosition) > SPOT_PRESENCE_RADIUS_METERS) continue;
    const senderUsername = cleanText(sender.username, 'driver');
    const spotName = cleanText(currentSpot.name, 'a spot');
    results.push(...await Promise.all(friends.map(friendUid => sendPushToUser({
      userId: friendUid,
      settingName: 'friendAtSpotNotifications',
      deliveryKey: `friend_at_spot_visit:${userId}:${spot.id}:${enteredAt}`,
      notificationId: `spot_visit_${friendUid}_${userId}_${spot.id}_${enteredAt}`,
      title: 'Live location',
      body: `@${senderUsername} is at ${spotName}.`,
      data: {type: 'friend_at_spot', spotId: spot.id, spotName, friendUid: userId,
        actorUserId: userId, friendUsername: senderUsername, lat: livePosition.lat, lng: livePosition.lng},
    }))));
    await db.runTransaction(async tx => {
      const doc = await tx.get(stateRef);
      const state = doc.data();
      if (state?.session !== observation.state.session || state.visits?.[spot.id]?.enteredAt !== enteredAt) return;
      tx.set(stateRef, {...state, visits: {...state.visits, [spot.id]: {...state.visits[spot.id], notified: true}}});
    });
  }
  return results;
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
  const fallbackRecipients = cleanStringArray(fallbackUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );

  if (explicitRecipients.length) {
    // Explicit recipients are normally the residents of the selected
    // community. Always retain targeted recipients too (for example a topic
    // author who is participating in another country's forum).
    return [...new Set([...explicitRecipients, ...fallbackRecipients])];
  }

  if (cleanText(payload.audience) === 'all_users') {
    const usersSnapshot = await db.collection('users').get();
    return [...new Set([...usersSnapshot.docs.map((doc) => doc.id), ...fallbackRecipients])].filter((id) => id !== userId);
  }

  return fallbackRecipients;
}

function recipientNotificationId(payload, fallbackBase, recipientUserId) {
  const base = cleanText(payload.notificationId, fallbackBase);
  return base.endsWith(`_${recipientUserId}`) ? base : `${base}_${recipientUserId}`;
}

const GLOBAL_CHAT_DAILY_PUSH_COOLDOWN_MS = 24 * 60 * 60 * 1000;

async function claimGlobalChatDailyPushWindow(
  senderUid,
  messageId,
  communityCountry,
) {
  const country = countryKey(communityCountry) || 'LV';
  const globalRef = db.collection('push_throttles').doc(`global_chat_${country}`);
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
        countryCode: country,
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
  const communityCountry = countryKey(message.countryCode) || 'LV';

  const results = [];
  const replyTarget = await globalChatReplyTarget(message, senderUid);
  if (replyTarget && !payload._mentionRecipientIds?.includes(replyTarget.recipientUserId)) {
    try {
      results.push(
        await sendPushToUser({
          userId: replyTarget.recipientUserId,
          settingName: 'newMessageNotifications',
          // A direct reply follows the participant even when they are writing
          // in a community outside their registered country.
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
      recipientUserId !== replyTarget?.recipientUserId &&
      !payload._mentionRecipientIds?.includes(recipientUserId),
  );
  if (!recipientUserIds.length) {
    return results;
  }

  const pushWindow = await claimGlobalChatDailyPushWindow(
    senderUid,
    messageId,
    communityCountry,
  );
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
        communityCountry,
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

async function handleForumTopicCreated(userId, payload) {
  const topicId = cleanText(payload.topicId);
  if (!topicId || topicId.includes('/')) return [];
  const snapshot = await db.collection('forum_topics').doc(topicId).get();
  const topic = snapshot.data();
  if (!topic || topic.status !== 'approved') return [];
  const authorId = cleanText(topic.authorId);
  if (userId !== authorId) {
    const actor = (await db.collection('users').doc(userId).get()).data() || {};
    if (!userCanModerateCommunityCountry(actor, savedCommunityCountry(topic))) {
      throw new Error('This topic is outside your assigned countries');
    }
  }
  const users = await db.collection('users').get();
  const topicTitle = cleanText(topic.title, 'Forum topic');
  const results = [];
  for (let start = 0; start < users.docs.length; start += 50) {
    results.push(...await Promise.all(users.docs.slice(start, start + 50)
      .filter(doc => doc.id !== authorId)
      .map(doc => sendPushToUser({
        userId: doc.id,
        settingName: 'commentNotifications',
        deliveryKey: `forum_topic_created:${topicId}`,
        notificationId: `forum_topic_created_${topicId}_${doc.id}`,
        title: `New forum topic: ${topicTitle}`,
        body: shortText(topic.description, `@${cleanText(topic.authorName, 'driver')} created a topic.`),
        data: {type: 'forum_topic_created', topicId, topicTitle, senderUid: authorId},
      }))));
  }
  return results;
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

  if (topic.status !== 'approved' || cleanText(reply.userId) !== userId) {
    return [];
  }

  const authorId = cleanText(topic.authorId);
  const replyToMessageId = cleanText(reply.replyToMessageId);
  let repliedToUserId = '';
  if (replyToMessageId) {
    const originalReplySnapshot = await topicRef
      .collection('replies')
      .doc(replyToMessageId)
      .get();
    repliedToUserId = cleanText(originalReplySnapshot.data()?.userId);
    if (repliedToUserId === userId) {
      repliedToUserId = '';
    }
  }
  const targetedRecipientIds = new Set(
    [authorId, repliedToUserId].filter(
      (recipientUserId) => recipientUserId && recipientUserId !== userId,
    ),
  );
  const recipientUserIds = await communityRecipientIds(
    userId,
    {...payload, audience: 'all_users'},
    [...targetedRecipientIds],
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
  const communityCountry = countryKey(topic.countryCode) || 'LV';

  return Promise.all(
    recipientUserIds.filter(uid => !payload._mentionRecipientIds?.includes(uid)).map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName: 'commentNotifications',
        pushEnabled: targetedRecipientIds.has(recipientUserId),
        // Regional filtering applies to the general audience. Topic authors
        // and directly replied-to participants must still receive replies
        // while taking part in another country's forum.
        communityCountry: targetedRecipientIds.has(recipientUserId)
          ? ''
          : communityCountry,
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

function userCanModerateCommunityCountry(user, countryCode) {
  if (user.deleted === true || userHasActiveBan(user)) return false;
  if (user.role === 'admin') return true;
  const code = countryKey(countryCode);
  return !!code && (user.role === 'moderator' || user.globalModerator === true ||
    user.globalChatModerator === true) && cleanStringArray(user.moderatorCountryCodes).includes(code);
}

function savedCommunityCountry(data) {
  return Object.hasOwn(data, 'countryCode') ? countryKey(data.countryCode) : 'LV';
}

async function communityReviewRecipientIds(senderUid, country) {
  const snapshot = await db.collection('users').get();
  return snapshot.docs.filter(doc => doc.id !== senderUid &&
    userCanModerateCommunityCountry(doc.data() || {}, country)).map(doc => doc.id);
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

async function verifiedCommunityModeratorIds(userId, payload, country) {
  const requestedIds = cleanStringArray(payload.recipientUserIds).filter(
    (recipientUserId) => recipientUserId !== userId,
  );
  if (!requestedIds.length) {
    return [];
  }

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
        userCanModerateCommunityCountry(recipient, country)
      );
    })
    .map((snapshot) => snapshot.id);
}

async function activeStaffUserIdsExcept(userId) {
  const [adminSnapshot, moderatorSnapshot] = await Promise.all([
    db.collection('users').where('role', '==', 'admin').get(),
    db.collection('users').where('role', '==', 'moderator').get(),
  ]);
  const recipientUserIds = new Set();

  for (const snapshot of [adminSnapshot, moderatorSnapshot]) {
    for (const document of snapshot.docs) {
      const recipient = document.data() || {};
      if (
        document.id !== userId &&
        recipient.deleted !== true &&
        !userHasActiveBan(recipient) &&
        userIsStaff(recipient)
      ) {
        recipientUserIds.add(document.id);
      }
    }
  }

  return [...recipientUserIds];
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
  settingName = 'reviewNotifications',
  notificationCollection = 'admin_notifications',
}) {
  const title = fallbackTitle;
  const body = fallbackBody;

  return Promise.all(
    recipientUserIds.filter(uid => !payload._mentionRecipientIds?.includes(uid)).map((recipientUserId) =>
      sendPushToUser({
        userId: recipientUserId,
        settingName,
        deliveryKey,
        notificationId: recipientNotificationId(
          payload,
          fallbackNotificationId,
          recipientUserId,
        ),
        notificationCollection,
        title,
        body,
        data,
      }),
    ),
  );
}

async function handleForumTopicPending(userId, payload) {
  const topicId = cleanText(payload.topicId);
  if (!topicId) {
    return [];
  }

  const topicSnapshot = await db.collection('forum_topics').doc(topicId).get();
  if (!topicSnapshot.exists) {
    return [];
  }

  const topic = topicSnapshot.data() || {};
  if (cleanText(topic.authorId) !== userId || cleanText(topic.status) !== 'pending') {
    return [];
  }

  const recipientUserIds = await communityReviewRecipientIds(userId, savedCommunityCountry(topic));
  if (!recipientUserIds.length) {
    return [];
  }

  const topicTitle = cleanText(topic.title, 'Forum topic');
  const authorName = cleanText(topic.authorName, 'driver');
  const categoryId = cleanText(topic.categoryId, cleanText(topic.category));
  const spotId = cleanText(topic.spotId, cleanText(topic.temporarySpotId));

  return sendCommunityModeratorPush({
    userId,
    payload,
    recipientUserIds,
    deliveryKey: `forum_topic_pending:${topicId}`,
    fallbackNotificationId: `forum_topic_pending_${topicId}`,
    fallbackTitle: 'Forum topic waiting for review',
    fallbackBody: `${topicTitle} was submitted by @${authorName}.`,
    data: {
      type: 'forum_topic_pending',
      countryCode: savedCommunityCountry(topic),
      topicId,
      topicTitle,
      categoryId,
      spotId,
      senderUid: userId,
      senderUsername: authorName,
    },
  });
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

  const recipientUserIds = await verifiedCommunityModeratorIds(userId, payload, savedCommunityCountry(message));
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
      countryCode: savedCommunityCountry(message),
      messageId,
      senderUid: userId,
      senderUsername,
    },
  });
}

// Legacy clients use the same recipient policy and delivery claims.
async function handleForumReplyAdmin(userId, payload) {
  return handleForumReply(userId, payload);
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
      group_join_request: handleGroupJoinRequest,
      spot_decision: handleSpotDecision,
      spot_pending_review: handleSpotPendingReview,
      new_spot: handleNewSpot,
      temporary_event: handleTemporaryEvent,
      temporary_spot_today: handleTemporarySpotReminder,
      friend_at_spot: handleFriendAtSpot,
      friend_live_sharing: handleFriendLiveSharing,
      global_chat_message: handleGlobalChatMessage,
      global_chat_admin: handleGlobalChatAdmin,
      forum_topic_created: handleForumTopicCreated,
      forum_reply: handleForumReply,
      forum_topic_pending: handleForumTopicPending,
      forum_reply_admin: handleForumReplyAdmin,
    };
    const handler = handlers[type];

    if (!handler) {
      response.status(400).json({ status: 'error', message: 'Unsupported notification type.' });
      return;
    }

    const payload = {...(request.body || {}), _mentionRecipientIds: []};
    const mentionType = type === 'global_chat_admin' ? 'global_chat_message' : type === 'forum_reply_admin' ? 'forum_reply' : type;
    const mentions = await handleMentions(user.uid, mentionType, payload);
    payload._mentionRecipientIds = mentions.recipients;
    const results = [...mentions.results, ...(payload.mentionsOnly === true ? [] : await handler(user.uid, payload))];
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
