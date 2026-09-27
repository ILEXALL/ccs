const {createHash, randomUUID} = require('node:crypto');
const {planDocument, systemRoots} = require('./plan');
const taskId = value => createHash('sha256').update(value).digest('hex');

// The queue is private to the backend. A failed step is retried; completion is
// recorded only after every collection, media prefix and auth record is handled.
async function processDeletion({db, auth, media, jobRef, listPage, now = Date.now, budgetMs = 40000, maxDocuments = 250}) {
  const lease = randomUUID();
  const acquired = await db.runTransaction(async tx => {
    const snapshot = await tx.get(jobRef), job = snapshot.data();
    if (!job || job.status === 'complete' || (job.leaseUntil || 0) > now()) return false;
    // Existing signed upload URLs live for five minutes. Let them expire before
    // removing media, otherwise an in-flight upload could restore a deleted file.
    if (job.requestedAt && now() - job.requestedAt < 360000) return false;
    tx.update(jobRef, {lease, leaseUntil: now() + 300000});
    return true;
  });
  if (!acquired) return;
  const started = now();
  let processed = 0;
  try {
    let job = (await jobRef.get()).data();
    if (!job.initialized) {
      // Disabled accounts cannot mint new tokens while their data is removed.
      try {
        await auth.updateUser(jobRef.id, {disabled: true});
        await auth.revokeRefreshTokens(jobRef.id);
      } catch (error) {
        if (error.code !== 'auth/user-not-found') throw error;
      }
      const roots = await db.listCollections();
      const tasks = roots.filter(ref => !systemRoots.has(ref.id))
        .map(ref => ({kind: 'collection', path: ref.path, after: ''}));
      tasks.push(...['users', 'garage'].map(root => ({kind: 'media', path: `${root}/${jobRef.id}/`})));
      for (const task of tasks) {
        await jobRef.collection('tasks').doc(taskId(task.path)).set(task);
      }
      await jobRef.update({initialized: true, status: 'processing'});
    }
    while (now() - started < budgetMs && processed < maxDocuments) {
      const tasks = await jobRef.collection('tasks').orderBy('__name__').limit(1).get();
      if (tasks.empty) {
        // A reply may have been scanned before its source message. Keep only
        // its path during the scan, then resolve against the deleted-message
        // index. There is no need to traverse the whole database a second time.
        const replies = await jobRef.collection('reply_checks').orderBy('__name__').limit(1).get();
        if (!replies.empty) {
          const check = replies.docs[0];
          await db.runTransaction(async tx => {
            const ref = db.doc(check.data().path);
            const current = await tx.get(ref);
            const replyId = current.data()?.replyToMessageId;
            const source = typeof replyId === 'string' && replyId && !replyId.includes('/')
              ? jobRef.collection('references').doc(taskId(`${ref.parent.path}/${replyId}`)) : null;
            const deleted = source ? (await tx.get(source)).exists : false;
            if (current.exists && deleted) {
              const data = {...current.data()};
              for (const key of Object.keys(data).filter(key => key.startsWith('replyTo'))) data[key] = '';
              tx.set(ref, data);
            }
            tx.delete(check.ref);
          });
          processed++;
          continue;
        }
        // Bound index cleanup too; do not spend the entire function duration
        // recursively deleting a large temporary reference collection.
        const references = await jobRef.collection('references').limit(Math.min(25, maxDocuments - processed)).get();
        if (!references.empty) {
          const batch = db.batch();
          for (const reference of references.docs) batch.delete(reference.ref);
          await batch.commit();
          processed += references.size;
          continue;
        }
        // Authentication deletion is last, so a failure does not lose ownership.
        try { await auth.deleteUser(jobRef.id); }
        catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
        await db.recursiveDelete(db.collection('users').doc(jobRef.id));
        const batch = db.batch();
        batch.set(db.collection('account_deletion_receipts').doc(job.receiptHash),
          {status: 'complete', completedAt: now()});
        // Retain a minimal revocation tombstone. No profile, email or content.
        batch.set(jobRef, {status: 'complete', completedAt: now(), leaseUntil: 0});
        await batch.commit();
        return;
      }
      const taskDoc = tasks.docs[0];
      let task = taskDoc.data();
      if (task.kind === 'media') {
        processed++;
        if (await media.deletePrefixPage(task.path)) await taskDoc.ref.delete();
        continue;
      }
      if (!task.pendingPaths?.length) {
        if (task.lastPage) { await taskDoc.ref.delete(); continue; }
        const page = await listPage(task.path, task.pageToken || '');
        task = {...task, pendingPaths: page.paths, pageToken: page.nextPageToken, lastPage: !page.nextPageToken};
        await taskDoc.ref.update({pendingPaths: task.pendingPaths, pageToken: task.pageToken, lastPage: task.lastPage});
        if (!task.pendingPaths.length) continue;
      }
      for (const documentPath of [...task.pendingPaths]) {
        const ref = db.doc(documentPath);
        const children = await ref.listCollections();
        await db.runTransaction(async tx => {
          const current = await tx.get(ref);
          const replyId = current.data()?.replyToMessageId;
          const replyRef = typeof replyId === 'string' && replyId && !replyId.includes('/')
            ? jobRef.collection('references').doc(taskId(`${ref.parent.path}/${replyId}`)) : null;
          const replyWasDeleted = replyRef ? (await tx.get(replyRef)).exists : false;
          const account = {uid: jobRef.id, username: job.username || '', replyWasDeleted};
          const plan = current.exists ? planDocument(ref.path, current.data(), account) : {action: 'skip'};
          for (const child of children) tx.set(jobRef.collection('tasks').doc(taskId(child.path)),
            {kind: 'collection', path: child.path, after: ''});
          if (plan.action === 'delete' && ref.parent.id === 'spots') {
            const prefix = `spots/${ref.id}/`;
            tx.set(jobRef.collection('tasks').doc(taskId(prefix)), {kind: 'media', path: prefix});
          }
          if (plan.action === 'delete' && ['messages', 'global_chat', 'replies'].includes(ref.parent.id)) {
            tx.set(jobRef.collection('references').doc(taskId(ref.path)), {deleted: true});
          }
          if (replyRef && !replyWasDeleted && plan.action !== 'delete') {
            tx.set(jobRef.collection('reply_checks').doc(taskId(ref.path)), {path: ref.path});
          }
          // Keep the disabled profile until all work finishes; legacy backend
          // checks also see deleted=true while queues drain.
          if (ref.path !== `users/${jobRef.id}`) {
            if (plan.action === 'delete') tx.delete(ref);
            if (plan.action === 'replace') tx.set(ref, plan.data);
          }
          tx.update(taskDoc.ref, {pendingPaths: task.pendingPaths.slice(1)});
        });
        task.pendingPaths = task.pendingPaths.slice(1);
        processed++;
        if (now() - started >= budgetMs || processed >= maxDocuments) break;
      }
    }
  } finally {
    await db.runTransaction(async tx => {
      const snapshot = await tx.get(jobRef);
      if (snapshot.data()?.lease === lease) tx.update(jobRef, {leaseUntil: 0});
    });
  }
}
module.exports = {processDeletion};
