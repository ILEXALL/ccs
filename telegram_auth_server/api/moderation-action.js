const { admin, db } = require('../lib/firebase-admin');

function cleanString(value, fallback = '') {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function stringArray(value) {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === 'string' && item.trim())
    : [];
}

function uniqueStrings(values) {
  return [...new Set(stringArray(values))];
}

function isStaff(user) {
  return user.role === 'admin' || user.role === 'moderator';
}

function isActiveUser(user) {
  return user && user.deleted !== true && user.banned !== true;
}

function chatOwnerUid(chat) {
  const memberIds = stringArray(chat.memberIds);
  return cleanString(chat.ownerUid, memberIds[0] || '');
}

function actorCanManageChat(actorUid, actorUser, chat) {
  const memberIds = stringArray(chat.memberIds);
  const moderatorIds = stringArray(chat.moderatorIds);

  return (
    chat.isGroup === true &&
    memberIds.includes(actorUid) &&
    (chatOwnerUid(chat) === actorUid ||
      moderatorIds.includes(actorUid) ||
      isStaff(actorUser))
  );
}

function compactMemberFields(chat, targetUid) {
  const memberIds = stringArray(chat.memberIds);
  const usernames = stringArray(chat.memberUsernames);
  const photoUrls = Array.isArray(chat.memberPhotoUrls)
    ? chat.memberPhotoUrls.map((value) =>
        typeof value === 'string' ? value : '',
      )
    : [];

  const nextIds = [];
  const nextUsernames = [];
  const nextPhotoUrls = [];

  memberIds.forEach((uid, index) => {
    if (uid === targetUid) {
      return;
    }

    nextIds.push(uid);
    nextUsernames.push(usernames[index] || 'ccs_driver');
    nextPhotoUrls.push(photoUrls[index] || '');
  });

  return {
    memberIds: nextIds,
    memberUsernames: nextUsernames,
    memberPhotoUrls: nextPhotoUrls,
  };
}

async function authenticatedUser(req) {
  const authorization = cleanString(req.headers.authorization);

  if (!authorization.startsWith('Bearer ')) {
    return null;
  }

  return admin.auth().verifyIdToken(authorization.slice('Bearer '.length));
}

async function actorContext(req) {
  const token = await authenticatedUser(req);

  if (!token?.uid) {
    return null;
  }

  const userSnapshot = await db.collection('users').doc(token.uid).get();
  const user = userSnapshot.data() || {};

  if (!isActiveUser(user)) {
    return null;
  }

  return { uid: token.uid, user };
}

async function actorIsGlobalModerator(uid, user) {
  if (isStaff(user) || user.globalModerator === true || user.globalChatModerator === true) {
    return true;
  }

  const configSnapshot = await db.collection('app_config').doc('global_chat').get();
  const config = configSnapshot.data() || {};
  const moderatorIds = [
    ...stringArray(config.moderatorIds),
    ...stringArray(config.globalModeratorIds),
  ];

  return moderatorIds.includes(uid);
}

function moderationLogRef() {
  return db.collection('moderation_logs').doc();
}

function writeModerationLog(transaction, data) {
  transaction.set(moderationLogRef(), {
    ...data,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function requireBodyString(body, key) {
  const value = cleanString(body?.[key]);

  if (!value) {
    throw new Error(`Missing ${key}`);
  }

  return value;
}

async function setChatModerator({ actor, body }) {
  const chatId = requireBodyString(body, 'chatId');
  const targetUserId = requireBodyString(body, 'targetUserId');
  const makeModerator = body.makeModerator === true;
  const chatRef = db.collection('chats').doc(chatId);

  await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);

    if (!chatSnapshot.exists) {
      throw new Error('Chat not found');
    }

    const chat = chatSnapshot.data() || {};
    const memberIds = stringArray(chat.memberIds);

    if (!actorCanManageChat(actor.uid, actor.user, chat)) {
      throw new Error('No permission to manage this chat');
    }

    if (!memberIds.includes(targetUserId)) {
      throw new Error('Target user is not a chat member');
    }

    if (targetUserId === actor.uid || targetUserId === chatOwnerUid(chat)) {
      throw new Error('This role cannot be changed');
    }

    const moderatorIds = uniqueStrings(chat.moderatorIds);
    const nextModeratorIds = makeModerator
      ? uniqueStrings([...moderatorIds, targetUserId])
      : moderatorIds.filter((uid) => uid !== targetUserId);

    transaction.update(chatRef, {
      moderatorIds: nextModeratorIds,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: makeModerator ? 'chat_moderator_added' : 'chat_moderator_removed',
      actorUid: actor.uid,
      targetUserId,
      chatId,
    });
  });
}

async function removeChatMember({ actor, body }) {
  const chatId = requireBodyString(body, 'chatId');
  const targetUserId = requireBodyString(body, 'targetUserId');
  const chatRef = db.collection('chats').doc(chatId);

  await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);

    if (!chatSnapshot.exists) {
      throw new Error('Chat not found');
    }

    const chat = chatSnapshot.data() || {};
    const memberIds = stringArray(chat.memberIds);
    const moderatorIds = uniqueStrings(chat.moderatorIds);

    if (!actorCanManageChat(actor.uid, actor.user, chat)) {
      throw new Error('No permission to manage this chat');
    }

    if (!memberIds.includes(targetUserId)) {
      throw new Error('Target user is not a chat member');
    }

    if (targetUserId === actor.uid || targetUserId === chatOwnerUid(chat)) {
      throw new Error('This member cannot be removed');
    }

    if (
      !isStaff(actor.user) &&
      chatOwnerUid(chat) !== actor.uid &&
      moderatorIds.includes(targetUserId)
    ) {
      throw new Error('Moderators can remove regular members only');
    }

    const nextMembers = compactMemberFields(chat, targetUserId);

    transaction.update(chatRef, {
      ...nextMembers,
      moderatorIds: moderatorIds.filter((uid) => uid !== targetUserId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: 'chat_member_removed',
      actorUid: actor.uid,
      targetUserId,
      chatId,
    });
  });
}

async function addChatMembers({ actor, body }) {
  const chatId = requireBodyString(body, 'chatId');
  const targetUserIds = uniqueStrings(body.targetUserIds).slice(0, 25);

  if (!targetUserIds.length) {
    throw new Error('Missing target users');
  }

  const targetSnapshots = await db.getAll(
    ...targetUserIds.map((uid) => db.collection('users').doc(uid)),
  );
  const targetsById = new Map(
    targetSnapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => [snapshot.id, snapshot.data() || {}]),
  );
  const chatRef = db.collection('chats').doc(chatId);

  await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);

    if (!chatSnapshot.exists) {
      throw new Error('Chat not found');
    }

    const chat = chatSnapshot.data() || {};

    if (!actorCanManageChat(actor.uid, actor.user, chat)) {
      throw new Error('No permission to manage this chat');
    }

    const memberIds = stringArray(chat.memberIds);
    const memberUsernames = stringArray(chat.memberUsernames);
    const memberPhotoUrls = Array.isArray(chat.memberPhotoUrls)
      ? chat.memberPhotoUrls.map((value) =>
          typeof value === 'string' ? value : '',
        )
      : [];
    const addedUserIds = [];

    for (const uid of targetUserIds) {
      if (memberIds.includes(uid)) {
        continue;
      }

      const user = targetsById.get(uid);
      if (!isActiveUser(user)) {
        continue;
      }

      memberIds.push(uid);
      memberUsernames.push(
        cleanString(user.username, cleanString(user.displayName, 'ccs_driver')),
      );
      memberPhotoUrls.push(cleanString(user.photoUrl));
      addedUserIds.push(uid);
    }

    if (!addedUserIds.length) {
      return;
    }

    transaction.update(chatRef, {
      memberIds,
      memberUsernames,
      memberPhotoUrls,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: 'chat_members_added',
      actorUid: actor.uid,
      targetUserIds: addedUserIds,
      chatId,
    });
  });
}

async function deleteChatMessage({ actor, body }) {
  const chatId = requireBodyString(body, 'chatId');
  const messageId = requireBodyString(body, 'messageId');
  const chatRef = db.collection('chats').doc(chatId);
  const messageRef = chatRef.collection('messages').doc(messageId);

  await db.runTransaction(async (transaction) => {
    const [chatSnapshot, messageSnapshot] = await Promise.all([
      transaction.get(chatRef),
      transaction.get(messageRef),
    ]);

    if (!chatSnapshot.exists || !messageSnapshot.exists) {
      throw new Error('Message not found');
    }

    const chat = chatSnapshot.data() || {};
    const message = messageSnapshot.data() || {};
    const senderUid = cleanString(message.senderUid);

    if (senderUid !== actor.uid && !actorCanManageChat(actor.uid, actor.user, chat)) {
      throw new Error('No permission to delete this message');
    }

    transaction.delete(messageRef);
    writeModerationLog(transaction, {
      action: 'chat_message_deleted',
      actorUid: actor.uid,
      targetUserId: senderUid,
      chatId,
      messageId,
    });
  });
}

async function deleteGlobalMessage({ actor, body }) {
  const messageId = requireBodyString(body, 'messageId');

  if (!(await actorIsGlobalModerator(actor.uid, actor.user))) {
    throw new Error('No permission to moderate global chat');
  }

  const messageRef = db.collection('global_chat').doc(messageId);

  await db.runTransaction(async (transaction) => {
    const messageSnapshot = await transaction.get(messageRef);

    if (!messageSnapshot.exists) {
      return;
    }

    const message = messageSnapshot.data() || {};

    transaction.delete(messageRef);
    writeModerationLog(transaction, {
      action: 'global_chat_message_deleted',
      actorUid: actor.uid,
      targetUserId: cleanString(message.userId),
      messageId,
    });
  });
}

async function clearGlobalChat({ actor }) {
  if (!(await actorIsGlobalModerator(actor.uid, actor.user))) {
    throw new Error('No permission to moderate global chat');
  }

  const snapshot = await db
    .collection('global_chat')
    .orderBy('timestamp', 'desc')
    .limit(100)
    .get();
  const batch = db.batch();

  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  batch.set(moderationLogRef(), {
    action: 'global_chat_cleared',
    actorUid: actor.uid,
    messageCount: snapshot.size,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

async function setForumTopicPinned({ actor, body }) {
  if (!isStaff(actor.user)) {
    throw new Error('No permission to pin forum topics');
  }

  const topicId = requireBodyString(body, 'topicId');
  const pinned = body.pinned === true;
  const topicRef = db.collection('forum_topics').doc(topicId);

  await db.runTransaction(async (transaction) => {
    const topicSnapshot = await transaction.get(topicRef);

    if (!topicSnapshot.exists) {
      throw new Error('Topic not found');
    }

    transaction.update(topicRef, {
      isPinned: pinned,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: pinned ? 'forum_topic_pinned' : 'forum_topic_unpinned',
      actorUid: actor.uid,
      topicId,
    });
  });
}

async function updateForumTopicHeader({ actor, body }) {
  const topicId = requireBodyString(body, 'topicId');
  const description = requireBodyString(body, 'description');
  const topicRef = db.collection('forum_topics').doc(topicId);

  await db.runTransaction(async (transaction) => {
    const topicSnapshot = await transaction.get(topicRef);

    if (!topicSnapshot.exists) {
      throw new Error('Topic not found');
    }

    const topic = topicSnapshot.data() || {};
    if (!isStaff(actor.user) && cleanString(topic.authorId) !== actor.uid) {
      throw new Error('No permission to edit this topic');
    }

    transaction.update(topicRef, {
      description,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: 'forum_topic_header_updated',
      actorUid: actor.uid,
      targetUserId: cleanString(topic.authorId),
      topicId,
    });
  });
}

async function deleteForumTopic({ actor, body }) {
  const topicId = requireBodyString(body, 'topicId');
  const topicRef = db.collection('forum_topics').doc(topicId);

  await db.runTransaction(async (transaction) => {
    const topicSnapshot = await transaction.get(topicRef);

    if (!topicSnapshot.exists) {
      return;
    }

    const topic = topicSnapshot.data() || {};
    if (!isStaff(actor.user) && cleanString(topic.authorId) !== actor.uid) {
      throw new Error('No permission to delete this topic');
    }

    transaction.delete(topicRef);
    writeModerationLog(transaction, {
      action: 'forum_topic_deleted',
      actorUid: actor.uid,
      targetUserId: cleanString(topic.authorId),
      topicId,
    });
  });
}

async function deleteForumReply({ actor, body }) {
  const topicId = requireBodyString(body, 'topicId');
  const replyId = requireBodyString(body, 'replyId');
  const topicRef = db.collection('forum_topics').doc(topicId);
  const replyRef = topicRef.collection('replies').doc(replyId);

  await db.runTransaction(async (transaction) => {
    const [topicSnapshot, replySnapshot] = await Promise.all([
      transaction.get(topicRef),
      transaction.get(replyRef),
    ]);

    if (!topicSnapshot.exists || !replySnapshot.exists) {
      return;
    }

    const topic = topicSnapshot.data() || {};
    const reply = replySnapshot.data() || {};
    const replyAuthorId = cleanString(reply.userId);

    if (
      !isStaff(actor.user) &&
      cleanString(topic.authorId) !== actor.uid &&
      replyAuthorId !== actor.uid
    ) {
      throw new Error('No permission to delete this reply');
    }

    transaction.delete(replyRef);
    transaction.update(topicRef, {
      repliesCount: admin.firestore.FieldValue.increment(-1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    writeModerationLog(transaction, {
      action: 'forum_reply_deleted',
      actorUid: actor.uid,
      targetUserId: replyAuthorId,
      topicId,
      replyId,
    });
  });
}

const handlers = {
  set_chat_moderator: setChatModerator,
  remove_chat_member: removeChatMember,
  add_chat_members: addChatMembers,
  delete_chat_message: deleteChatMessage,
  delete_global_message: deleteGlobalMessage,
  clear_global_chat: clearGlobalChat,
  set_forum_topic_pinned: setForumTopicPinned,
  update_forum_topic_header: updateForumTopicHeader,
  delete_forum_topic: deleteForumTopic,
  delete_forum_reply: deleteForumReply,
};

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  }

  try {
    const actor = await actorContext(req);

    if (!actor) {
      return res.status(401).json({ ok: false, error: 'Unauthorized' });
    }

    const action = cleanString(req.body?.action);
    const actionHandler = handlers[action];

    if (!actionHandler) {
      return res.status(400).json({ ok: false, error: 'Unknown action' });
    }

    await actionHandler({ actor, body: req.body || {} });
    return res.status(200).json({ ok: true });
  } catch (error) {
    return res.status(403).json({
      ok: false,
      error: cleanString(error?.message, 'Moderation action failed'),
    });
  }
};
