'use strict';

const {
  applicationDefault,
  cert,
  getApps,
  initializeApp,
} = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const {
  FieldValue,
  GeoPoint,
  getFirestore,
} = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

function firstEnvironmentValue(...names) {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return '';
}

function firebaseCredential() {
  const rawServiceAccount = firstEnvironmentValue(
    'FIREBASE_SERVICE_ACCOUNT_JSON',
    'FIREBASE_ADMIN_SERVICE_ACCOUNT_JSON',
  );
  if (rawServiceAccount) {
    return cert(JSON.parse(rawServiceAccount));
  }

  const projectId = firstEnvironmentValue(
    'FIREBASE_PROJECT_ID',
    'FIREBASE_ADMIN_PROJECT_ID',
    'GCLOUD_PROJECT',
  );
  const clientEmail = firstEnvironmentValue(
    'FIREBASE_CLIENT_EMAIL',
    'FIREBASE_ADMIN_CLIENT_EMAIL',
  );
  const privateKey = firstEnvironmentValue(
    'FIREBASE_PRIVATE_KEY',
    'FIREBASE_ADMIN_PRIVATE_KEY',
  ).replace(/\\n/g, '\n');

  if (projectId && clientEmail && privateKey) {
    return cert({ projectId, clientEmail, privateKey });
  }

  return applicationDefault();
}

function ensureFirebaseAdmin() {
  if (getApps().length === 0) {
    initializeApp({ credential: firebaseCredential() });
  }
}

function parseBody(req) {
  if (req.body && typeof req.body === 'object') {
    return req.body;
  }
  if (typeof req.body === 'string' && req.body.trim()) {
    return JSON.parse(req.body);
  }
  return {};
}

function bearerToken(req) {
  const header = String(req.headers.authorization || '').trim();
  return header.toLowerCase().startsWith('bearer ')
    ? header.slice(7).trim()
    : '';
}

function nonEmptyStrings(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item || '').trim())
    .filter(Boolean);
}

function notificationPreferenceEnabled(userData) {
  if (typeof userData.friendLiveShareNotifications === 'boolean') {
    return userData.friendLiveShareNotifications;
  }
  const nested = userData.settings;
  if (
    nested &&
    typeof nested === 'object' &&
    typeof nested.friendLiveShareNotifications === 'boolean'
  ) {
    return nested.friendLiveShareNotifications;
  }
  return true;
}

function chunks(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function safeNotificationId(value) {
  const clean = String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .slice(0, 700);
  return clean || `friend_live_share_${Date.now()}`;
}

async function commitNotificationHistory({
  db,
  recipients,
  notificationId,
  senderUid,
  senderUsername,
  senderName,
  title,
  body,
  latitude,
  longitude,
}) {
  const nowMillis = Date.now();
  let batch = db.batch();
  let operationCount = 0;

  for (const recipient of recipients) {
    const reference = db
      .collection('user_notifications')
      .doc(`${notificationId}_${recipient.uid}`);
    batch.set(
      reference,
      {
        userId: recipient.uid,
        type: 'friend_live_sharing',
        title,
        body,
        actorUserId: senderUid,
        actorUsername: senderUsername,
        friendUid: senderUid,
        friendUsername: senderUsername,
        friendName: senderName,
        friendLat: latitude,
        friendLng: longitude,
        friendCoordinates: new GeoPoint(latitude, longitude),
        distanceMeters: 0,
        spotId: '',
        spotName: '',
        spotCategory: '',
        read: false,
        lastNotifiedAtMillis: nowMillis,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    operationCount += 1;

    if (operationCount >= 400) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    await batch.commit();
  }
}

async function removeInvalidTokens(db, invalidTokensByUser) {
  const entries = [...invalidTokensByUser.entries()].filter(
    ([, tokens]) => tokens.size > 0,
  );
  if (entries.length === 0) return;

  let batch = db.batch();
  let operationCount = 0;
  for (const [uid, tokens] of entries) {
    batch.set(
      db.collection('users').doc(uid),
      {
        fcmTokens: FieldValue.arrayRemove(...tokens),
        fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    operationCount += 1;
    if (operationCount >= 400) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }
  }
  if (operationCount > 0) {
    await batch.commit();
  }
}

module.exports = async function liveLocationNotificationHandler(req, res) {
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    res.status(405).json({ ok: false, error: 'Method not allowed.' });
    return;
  }

  try {
    ensureFirebaseAdmin();

    const token = bearerToken(req);
    if (!token) {
      res.status(401).json({ ok: false, error: 'Missing Firebase ID token.' });
      return;
    }

    const decodedToken = await getAuth().verifyIdToken(token);
    const senderUid = String(decodedToken.uid || '').trim();
    if (!senderUid) {
      res.status(401).json({ ok: false, error: 'Invalid Firebase user.' });
      return;
    }

    const event = parseBody(req);
    if (event.type !== 'friend_live_sharing') {
      res.status(400).json({ ok: false, error: 'Unsupported notification type.' });
      return;
    }

    const latitude = Number(event.lat);
    const longitude = Number(event.lng);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      res.status(400).json({ ok: false, error: 'Invalid live-location coordinates.' });
      return;
    }

    const db = getFirestore();
    const senderReference = db.collection('users').doc(senderUid);
    const [senderSnapshot, friendshipsSnapshot] = await Promise.all([
      senderReference.get(),
      db
        .collection('friendships')
        .where('userIds', 'array-contains', senderUid)
        .get(),
    ]);

    const senderData = senderSnapshot.data() || {};
    const senderUsername =
      String(senderData.username || event.senderUsername || 'ccs_driver').trim() ||
      'ccs_driver';
    const senderName = String(senderData.name || senderUsername).trim() || senderUsername;
    const senderBlockedIds = new Set(nonEmptyStrings(senderData.blockedUserIds));

    const friendIds = new Set();
    for (const friendshipDocument of friendshipsSnapshot.docs) {
      const ids = nonEmptyStrings(friendshipDocument.data().userIds);
      for (const uid of ids) {
        if (uid !== senderUid && !senderBlockedIds.has(uid)) {
          friendIds.add(uid);
        }
      }
    }

    if (friendIds.size === 0) {
      res.status(404).json({
        ok: false,
        error: 'No accepted friends found for this user.',
        recipientCount: 0,
        tokenCount: 0,
        successCount: 0,
      });
      return;
    }

    const friendReferences = [...friendIds].map((uid) =>
      db.collection('users').doc(uid),
    );
    const friendSnapshots = await db.getAll(...friendReferences);
    const recipients = [];
    const tokenOwner = new Map();

    for (const friendSnapshot of friendSnapshots) {
      if (!friendSnapshot.exists) continue;
      const userData = friendSnapshot.data() || {};
      const uid = friendSnapshot.id;
      if (nonEmptyStrings(userData.blockedUserIds).includes(senderUid)) continue;
      if (userData.deleted === true || userData.banned === true) continue;
      if (!notificationPreferenceEnabled(userData)) continue;

      const tokens = [...new Set(nonEmptyStrings(userData.fcmTokens))];
      recipients.push({ uid, tokens });
      for (const fcmToken of tokens) {
        tokenOwner.set(fcmToken, uid);
      }
    }

    const allTokens = [...tokenOwner.keys()];
    if (allTokens.length === 0) {
      res.status(404).json({
        ok: false,
        error: 'Friends have no registered FCM tokens.',
        recipientCount: recipients.length,
        tokenCount: 0,
        successCount: 0,
      });
      return;
    }

    const notificationId = safeNotificationId(event.notificationId);
    const title = String(event.title || 'Live location').trim() || 'Live location';
    const body =
      String(event.body || `@${senderUsername} is sharing live location.`).trim() ||
      `@${senderUsername} is sharing live location.`;
    const expirationSeconds = Math.floor(Date.now() / 1000) + 5 * 60;
    let successCount = 0;
    let failureCount = 0;
    const invalidTokensByUser = new Map();

    for (const tokenChunk of chunks(allTokens, 500)) {
      const response = await getMessaging().sendEachForMulticast({
        tokens: tokenChunk,
        notification: { title, body },
        data: {
          type: 'friend_live_sharing',
          notificationId,
          senderUserId: senderUid,
          senderUsername,
          lat: String(latitude),
          lng: String(longitude),
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          ttl: 5 * 60 * 1000,
          notification: {
            sound: 'default',
          },
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': String(expirationSeconds),
          },
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      });

      successCount += response.successCount;
      failureCount += response.failureCount;
      response.responses.forEach((sendResponse, index) => {
        if (sendResponse.success) return;
        const code = sendResponse.error && sendResponse.error.code;
        if (
          code !== 'messaging/registration-token-not-registered' &&
          code !== 'messaging/invalid-registration-token'
        ) {
          return;
        }
        const failedToken = tokenChunk[index];
        const ownerUid = tokenOwner.get(failedToken);
        if (!ownerUid) return;
        if (!invalidTokensByUser.has(ownerUid)) {
          invalidTokensByUser.set(ownerUid, new Set());
        }
        invalidTokensByUser.get(ownerUid).add(failedToken);
      });
    }

    // History and stale-token cleanup happen after the time-sensitive send.
    await Promise.allSettled([
      commitNotificationHistory({
        db,
        recipients,
        notificationId,
        senderUid,
        senderUsername,
        senderName,
        title,
        body,
        latitude,
        longitude,
      }),
      removeInvalidTokens(db, invalidTokensByUser),
    ]);

    if (successCount === 0) {
      res.status(502).json({
        ok: false,
        error: 'FCM did not accept any live-location notifications.',
        recipientCount: recipients.length,
        tokenCount: allTokens.length,
        successCount,
        failureCount,
      });
      return;
    }

    res.status(200).json({
      ok: true,
      notificationId,
      recipientCount: recipients.length,
      tokenCount: allTokens.length,
      successCount,
      failureCount,
    });
  } catch (error) {
    console.error('Live-location notification failed:', error);
    res.status(500).json({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
