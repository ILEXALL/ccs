// Equality queries use Firestore's existing single-field indexes. Keep this
// list aligned with notification writers, including legacy client field names.
const identityFields = ['uid', 'userId', 'senderUid', 'authorId', 'authorUid',
  'addedByUid', 'fromUid', 'toUid', 'targetUserId', 'reportedUid', 'reporterUid',
  'actorUserId', 'actorUid', 'sourceUserUid', 'recipientUid', 'friendUid',
  'reviewedByUid', 'ownerUid', 'createdBy', 'updatedBy', 'deletedBy'];

function userIndexTasks(root, uid, username) {
  if (root === 'push_deliveries') return [queryTask(root, 'userId', uid)];
  if (root !== 'user_notifications') return null;
  const tasks = identityFields.flatMap(field => [field, `data.${field}`])
    .map(field => queryTask(root, field, uid));
  if (username) tasks.push(queryTask(root, 'replyToUsername', username));
  return tasks;
}
function queryTask(path, field, value, deleteAll = false) {
  return {kind: 'indexed', path, field, value, deleteAll};
}
function contentIndexTasks(path) {
  const parts = path.split('/');
  if (parts.length === 4 && parts[0] === 'chats' && parts[2] === 'messages') {
    return ['messageId', 'data.messageId'].map(field => ({
      ...queryTask('user_notifications', field, parts[3]), sourcePath: path,
    }));
  }
  const [root, id, extra] = path.split('/');
  if (extra || !['spots', 'forum_topics'].includes(root)) return [];
  const field = root === 'spots' ? 'spotId' : 'topicId';
  return [field, `data.${field}`].map(field => queryTask('user_notifications', field, id, true));
}
function indexTaskKey(task) {
  return JSON.stringify([task.path, task.field, task.value, task.sourcePath || '']);
}
async function indexedPage(db, task) {
  let query = db.collection(task.path).where(task.field, '==', task.value).orderBy('__name__').limit(25);
  if (task.pageToken) query = query.startAfter(db.doc(task.pageToken));
  const snapshot = await query.get();
  return {paths: snapshot.docs.map(doc => doc.ref.path),
    nextPageToken: snapshot.size === 25 ? snapshot.docs.at(-1).ref.path : ''};
}
module.exports = {userIndexTasks, contentIndexTasks, indexTaskKey, indexedPage};
