const {createHash, randomUUID} = require('node:crypto');
const {planDocument, systemRoots, contentReferencePaths} = require('./plan');
const {userIndexTasks, contentIndexTasks, indexTaskKey, indexedPage} = require('./indexed-tasks');
const taskId = value => createHash('sha256').update(value).digest('hex');

// The queue is private to the backend. A failed step is retried; completion is
// recorded only after every collection, media prefix and auth record is handled.
async function processDeletion({db, auth, media, jobRef, listPage, now = Date.now, budgetMs = 40000, maxDocuments = 1000}) {
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
  let hasDeletedSources;
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
      await jobRef.update({initialized: true, status: 'processing', indexedReferences: true});
      job.indexedReferences = true;
    }
    // Old jobs without deleted-content references can adopt targeted lookups.
    // Otherwise retain their full notification scan: old hashed references do
    // not retain source IDs and cannot safely be converted to indexed queries.
    if (!job.indexedReferences && (await jobRef.collection('references').limit(1).get()).empty) {
      await jobRef.update({indexedReferences: true});
      job.indexedReferences = true;
    }
    while (now() - started < budgetMs && processed < maxDocuments) {
      const tasks = await jobRef.collection('tasks').orderBy('__name__').limit(1).get();
      if (tasks.empty) {
        if (hasDeletedSources === undefined) {
          hasDeletedSources = !(await jobRef.collection('references').limit(1).get()).empty;
        }
        // With no deleted source content, there is nothing for deferred quote
        // or content checks to match. Remove only our temporary check records.
        if (!hasDeletedSources) {
          const limit = Math.min(250, maxDocuments - processed);
          const checks = await jobRef.collection('reply_checks').limit(limit).get();
          const content = checks.empty ? await jobRef.collection('content_checks').limit(limit).get() : null;
          const docs = checks.empty ? content.docs : checks.docs;
          if (docs.length) {
            const batch = db.batch();
            for (const check of docs) batch.delete(check.ref);
            await batch.commit();
            processed += docs.length;
            continue;
          }
        }
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
        const contentChecks = await jobRef.collection('content_checks').orderBy('__name__').limit(1).get();
        if (!contentChecks.empty) {
          const check = contentChecks.docs[0];
          await db.runTransaction(async tx => {
            const ref = db.doc(check.data().path);
            const current = await tx.get(ref);
            const paths = current.exists ? contentReferencePaths(ref.path, current.data()) : [];
            const deleted = await Promise.all(paths.map(path => tx.get(jobRef.collection('references').doc(taskId(path)))));
            if (deleted.some(snapshot => snapshot.exists)) tx.delete(ref);
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
      const indexed = task.kind === 'collection' &&
        (task.path !== 'user_notifications' || job.indexedReferences)
        ? userIndexTasks(task.path, jobRef.id, job.username) : null;
      if (indexed) {
        const batch = db.batch();
        for (const next of indexed) batch.set(jobRef.collection('tasks').doc(taskId(indexTaskKey(next))), next);
        batch.delete(taskDoc.ref);
        await batch.commit();
        continue;
      }
      if (task.kind === 'media') {
        processed++;
        if (await media.deletePrefixPage(task.path)) await taskDoc.ref.delete();
        continue;
      }
      if (!task.pendingPaths?.length) {
        if (task.lastPage) { await taskDoc.ref.delete(); continue; }
        const page = task.kind === 'indexed' ? await indexedPage(db, task)
          : await listPage(task.path, task.pageToken || '');
        task = {...task, pendingPaths: page.paths, pageToken: page.nextPageToken, lastPage: !page.nextPageToken};
        await taskDoc.ref.update({pendingPaths: task.pendingPaths, pageToken: task.pageToken, lastPage: task.lastPage});
        if (!task.pendingPaths.length) continue;
      }
      while (task.pendingPaths.length && now() - started < budgetMs && processed < maxDocuments) {
        // Bound concurrent enumeration and transaction size. Commit the cursor
        // with the whole batch so a failure cannot skip any document.
        const refs = task.pendingPaths.slice(0, Math.min(25, maxDocuments - processed)).map(path => db.doc(path));
        const descendants = await Promise.all(refs.map(ref => ref.listCollections()));
        await db.runTransaction(async tx => {
          const snapshots = await tx.getAll(...refs);
          const replyRefs = snapshots.map((current, index) => {
            const ref = refs[index], replyId = current.data()?.replyToMessageId;
            return typeof replyId === 'string' && replyId && !replyId.includes('/')
            ? jobRef.collection('references').doc(taskId(`${ref.parent.path}/${replyId}`)) : null;
          });
          const uniqueReplyRefs = [...new Map(replyRefs.filter(Boolean).map(ref => [ref.path, ref])).values()];
          const deletedReplies = new Set(uniqueReplyRefs.length
            ? (await tx.getAll(...uniqueReplyRefs)).filter(doc => doc.exists).map(doc => doc.ref.path) : []);
          // Complete every read before any write. Replies to a source deleted
          // in this same batch are resolved by the existing deferred checks.
          for (let index = 0; index < refs.length; index++) {
            const ref = refs[index], current = snapshots[index], children = descendants[index];
            const replyRef = replyRefs[index];
            const replyWasDeleted = replyRef ? deletedReplies.has(replyRef.path) : false;
            const account = {uid: jobRef.id, username: job.username || '', replyWasDeleted};
            const plan = current.exists
              ? task.deleteAll || (task.sourcePath && contentReferencePaths(ref.path, current.data()).includes(task.sourcePath))
                ? {action: 'delete'} : planDocument(ref.path, current.data(), account)
              : {action: 'skip'};
            for (const child of children) tx.set(jobRef.collection('tasks').doc(taskId(child.path)),
              {kind: 'collection', path: child.path, after: '',
                // Firestore deleting a document does not delete its subcollections.
                deleteAll: task.deleteAll === true || plan.action === 'delete'});
            if (plan.action === 'delete' && ref.parent.id === 'spots') {
              const prefix = `spots/${ref.id}/`;
              tx.set(jobRef.collection('tasks').doc(taskId(prefix)), {kind: 'media', path: prefix});
            }
            if (plan.action === 'delete' && ['messages', 'global_chat', 'replies', 'spots', 'forum_topics'].includes(ref.parent.id)) {
              tx.set(jobRef.collection('references').doc(taskId(ref.path)), {deleted: true});
              for (const next of contentIndexTasks(ref.path)) {
                tx.set(jobRef.collection('tasks').doc(taskId(indexTaskKey(next))), next);
              }
            }
            if (replyRef && !replyWasDeleted && plan.action !== 'delete') {
              tx.set(jobRef.collection('reply_checks').doc(taskId(ref.path)), {path: ref.path});
            }
            if (current.exists && plan.action !== 'delete' && contentReferencePaths(ref.path, current.data()).length) {
              tx.set(jobRef.collection('content_checks').doc(taskId(ref.path)), {path: ref.path});
            }
            // Keep the disabled profile until all work finishes; legacy backend
            // checks also see deleted=true while queues drain.
            if (ref.path !== `users/${jobRef.id}`) {
              if (plan.action === 'delete') tx.delete(ref);
              if (plan.action === 'replace') tx.set(ref, plan.data);
            }
          }
          tx.update(taskDoc.ref, {pendingPaths: task.pendingPaths.slice(refs.length)});
          tx.update(jobRef, {lastProgressAt: now(), documentsProcessed: (job.documentsProcessed || 0) + processed + refs.length});
        });
        task.pendingPaths = task.pendingPaths.slice(refs.length);
        processed += refs.length;
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
