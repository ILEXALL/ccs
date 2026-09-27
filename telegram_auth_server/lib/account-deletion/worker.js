const {createHash, randomUUID} = require('node:crypto');
const {planDocument, systemRoots, referencedSpotIds, scrubMedia} = require('./plan');
const {dependentQueries} = require('./relationships');
const taskId = value => createHash('sha256').update(value).digest('hex');

// The queue is private to the backend. A failed step is retried; completion is
// recorded only after every collection, media prefix and auth record is handled.
async function processDeletion({db, auth, media, jobRef, listPage, now = Date.now, budgetMs = 40000, maxDocuments = 10000}) {
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
    // Upgrade resumable jobs created before the upload ledger was introduced.
    if (!job.mediaIndexInitialized) {
      const batch = db.batch();
      const path = `media_uploads/${jobRef.id}`;
      batch.set(jobRef.collection('tasks').doc(taskId(path)), {kind: 'uploads', path});
      batch.update(jobRef, {mediaIndexInitialized: true});
      await batch.commit();
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
        const mediaChecks = await jobRef.collection('media_checks').limit(1).get();
        if (!mediaChecks.empty) {
          const check = mediaChecks.docs[0];
          await db.runTransaction(async tx => {
            const ref = db.doc(check.data().path);
            const current = await tx.get(ref);
            const ids = referencedSpotIds(current.data());
            const deleted = ids.length ? await tx.getAll(...ids.map(id =>
              jobRef.collection('references').doc(taskId(`spots/${id}`)))) : [];
            const removed = new Set(ids.filter((_, index) => deleted[index].exists));
            if (current.exists) {
              const clean = scrubMedia(current.data(), jobRef.id, removed);
              if (clean.changed) tx.set(ref, clean.data);
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
      if (task.kind === 'dependents') {
        let query = (task.group ? db.collectionGroup(task.collection) : db.collection(task.collection))
          .where(task.field, '==', task.value).orderBy('__name__');
        if (task.after) query = query.startAfter(db.doc(task.after));
        const page = await query.limit(Math.min(25, maxDocuments - processed)).get();
        if (page.empty) { await taskDoc.ref.delete(); continue; }
        const batch = db.batch();
        for (const doc of page.docs) {
          // Recheck the relationship in the later deletion transaction.
          batch.set(jobRef.collection('tasks').doc(taskId(`dependent:${doc.ref.path}:${task.field}:${task.value}`)), {
            kind: 'collection', path: doc.ref.parent.path, pendingPaths: [doc.ref.path], lastPage: true,
            relationField: task.field, relationValue: task.value,
          });
        }
        batch.update(taskDoc.ref, {after: page.docs.at(-1).ref.path});
        await batch.commit();
        processed += page.size;
        continue;
      }
      if (task.kind === 'quotes') {
        const source = db.doc(task.path);
        const replies = await source.parent.where('replyToMessageId', '==', source.id)
          .limit(Math.min(25, maxDocuments - processed)).get();
        if (replies.empty) { await taskDoc.ref.delete(); continue; }
        await db.runTransaction(async tx => {
          const current = await tx.getAll(...replies.docs.map(doc => doc.ref));
          for (const reply of current) {
            if (reply.data()?.replyToMessageId !== source.id) continue;
            const clean = Object.fromEntries(Object.keys(reply.data()).filter(key => key.startsWith('replyTo')).map(key => [key, '']));
            tx.update(reply.ref, clean);
          }
        });
        processed += replies.size;
        continue;
      }
      if (task.kind === 'uploads') {
        // Firestore maintains the uid index atomically with upload reservation.
        // Restart at the beginning after deleting each row, so retries cannot
        // skip files, including uploads whose parent spot was never created.
        const uploads = await db.collection('media_uploads').where('uid', '==', jobRef.id).limit(1).get();
        if (uploads.empty) { await taskDoc.ref.delete(); continue; }
        const upload = uploads.docs[0];
        await media.deleteObject(upload.data().key);
        await upload.ref.delete();
        processed++;
        continue;
      }
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
      // One bounded transaction per page instead of a transaction and cursor
      // write per document. Child discovery remains exhaustive, including missing
      // parents; parallel RPCs are capped at one 25-document page.
      const pageLimit = ['spots', 'forum_topics'].includes(task.path) ? 5 : 25;
      const refs = task.pendingPaths.slice(0, Math.min(pageLimit, maxDocuments - processed)).map(path => db.doc(path));
      const childrenByPath = await Promise.all(refs.map(ref => ref.listCollections()));
      await db.runTransaction(async tx => {
        const snapshots = await tx.getAll(...refs);
        const replyRefs = snapshots.map(current => {
          const id = current.data()?.replyToMessageId;
          return typeof id === 'string' && id && !id.includes('/')
            ? jobRef.collection('references').doc(taskId(`${current.ref.parent.path}/${id}`)) : null;
        });
        const existingReplies = replyRefs.filter(Boolean);
        const deletedReplies = new Set(existingReplies.length
          ? (await tx.getAll(...existingReplies)).filter(doc => doc.exists).map(doc => doc.id) : []);
        for (let index = 0; index < snapshots.length; index++) {
          const current = snapshots[index], ref = current.ref;
          const replyRef = replyRefs[index];
          const replyWasDeleted = replyRef ? deletedReplies.has(replyRef.id) : false;
          const account = {uid: jobRef.id, username: job.username || '', replyWasDeleted};
          const relationshipMatches = task.relationField && current.exists && current.get(task.relationField) === task.relationValue;
          const plan = task.deleteTree || relationshipMatches ? {action: 'delete'} :
            current.exists ? planDocument(ref.path, current.data(), account) : {action: 'skip'};
          for (const child of childrenByPath[index]) tx.set(jobRef.collection('tasks').doc(taskId(child.path)),
            {kind: 'collection', path: child.path, ...(plan.action === 'delete' ? {deleteTree: true} : {})},
            // Escalating from a scan to subtree deletion must restart its cursor:
            // earlier unrelated replies now belong to a deleted parent too.
            {merge: plan.action !== 'delete'});
          if (plan.action === 'delete' && ref.parent.id === 'spots') {
            const prefix = `spots/${ref.id}/`;
            tx.set(jobRef.collection('tasks').doc(taskId(prefix)), {kind: 'media', path: prefix});
            tx.set(jobRef.collection('references').doc(taskId(ref.path)), {deleted: true});
          }
          if (plan.action === 'delete') {
            for (const dependent of dependentQueries(ref.path)) {
              tx.set(jobRef.collection('tasks').doc(taskId(JSON.stringify(dependent))), dependent);
            }
          }
          if (plan.action === 'delete' && ['messages', 'global_chat', 'replies'].includes(ref.parent.id)) {
            tx.set(jobRef.collection('references').doc(taskId(ref.path)), {deleted: true});
            // The native replyToMessageId index includes writes that arrived
            // after the broad scan passed this collection.
            tx.set(jobRef.collection('tasks').doc(taskId(`quotes:${ref.path}`)), {kind: 'quotes', path: ref.path});
          }
          if (replyRef && !replyWasDeleted && plan.action !== 'delete') {
            tx.set(jobRef.collection('reply_checks').doc(taskId(ref.path)), {path: ref.path});
          }
          if (plan.action !== 'delete' && referencedSpotIds(current.data()).length) {
            tx.set(jobRef.collection('media_checks').doc(taskId(ref.path)), {path: ref.path});
          }
          // Keep the disabled profile until all work finishes; legacy backend
          // checks also see deleted=true while queues drain.
          if (ref.path !== `users/${jobRef.id}`) {
            if (plan.action === 'delete') tx.delete(ref);
            if (plan.action === 'replace') tx.set(ref, plan.data);
          }
        }
        tx.update(taskDoc.ref, {pendingPaths: task.pendingPaths.slice(refs.length)});
      });
      processed += refs.length;
    }
  } finally {
    await db.runTransaction(async tx => {
      const snapshot = await tx.get(jobRef);
      if (snapshot.data()?.lease === lease) tx.update(jobRef, {leaseUntil: 0});
    });
  }
}
module.exports = {processDeletion};
