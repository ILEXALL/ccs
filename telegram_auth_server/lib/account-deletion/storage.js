const {S3Client, ListObjectsV2Command, DeleteObjectsCommand} = require('@aws-sdk/client-s3');

function storageAdapter(env = process.env, {firebaseStorage, s3Client} = {}) {
  for (const key of ['R2_ENDPOINT', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET_NAME', 'FIREBASE_STORAGE_BUCKET']) {
    if (!env[key]) throw new Error(`Deletion storage configuration missing: ${key}`);
  }
  if (!firebaseStorage) throw new Error('Firebase Storage cleanup is not configured');
  const bucket = firebaseStorage.bucket(env.FIREBASE_STORAGE_BUCKET);
  // Opt in only after auditing live and soft-deleted buckets in this project.
  // 403 and other failures must never be mistaken for a missing bucket.
  const missingAllowed = env.FIREBASE_STORAGE_ALLOW_MISSING === 'true';
  const absent = result => missingAllowed && result.status === 'rejected' && Number(result.reason?.code) === 404;
  const client = s3Client || new S3Client({region: 'auto', endpoint: env.R2_ENDPOINT,
    credentials: {accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY}});
  return {
    async verifyAccess() {
      const results = await Promise.allSettled([
        client.send(new ListObjectsV2Command({Bucket: env.R2_BUCKET_NAME, MaxKeys: 1})),
        bucket.getFiles({maxResults: 1, autoPaginate: false, versions: true}),
        bucket.getMetadata(),
      ]);
      const metadata = results[2].status === 'fulfilled' ? results[2].value[0] : null;
      const firebaseAbsent = absent(results[1]) && absent(results[2]);
      // Return only capabilities and retention settings, never object names,
      // URLs, credentials or provider error bodies. Read access alone does not
      // prove delete access; that requires a disposable-object test.
      return {
        ok: results[0].status === 'fulfilled' && (firebaseAbsent || results.slice(1).every(result => result.status === 'fulfilled')),
        firebaseAbsent,
        r2List: results[0].status === 'fulfilled',
        firebaseList: results[1].status === 'fulfilled',
        firebaseMetadata: results[2].status === 'fulfilled',
        firebaseSoftDeleteSeconds: metadata ? Number(metadata.softDeletePolicy?.retentionDurationSeconds || 0) : null,
        firebaseRetentionSeconds: metadata ? Number(metadata.retentionPolicy?.retentionPeriod || 0) : null,
      };
    },
    // Always restart at the prefix beginning: objects disappear after each batch.
    async deletePrefixPage(prefix) {
      if (!/^(users|garage|spots)\/[A-Za-z0-9_-]+\/$/.test(prefix)) throw new Error('Unsafe storage prefix');
      const page = await client.send(new ListObjectsV2Command({Bucket: env.R2_BUCKET_NAME, Prefix: prefix, MaxKeys: 500}));
      const objects = (page.Contents || []).map(item => ({Key: item.Key}));
      if (objects.length) {
        const result = await client.send(new DeleteObjectsCommand({Bucket: env.R2_BUCKET_NAME, Delete: {Objects: objects, Quiet: true}}));
        if (result.Errors?.length) throw new Error('Some media objects could not be deleted');
      }
      // Earlier builds uploaded to Firebase Storage. Delete every generation,
      // and do not treat permission/network failures as an empty bucket.
      const [files] = await bucket.getFiles({prefix, maxResults: 100, autoPaginate: false, versions: true})
        .catch(error => {
          if (missingAllowed && Number(error.code) === 404) return [[]];
          throw error;
        });
      for (let offset = 0; offset < files.length; offset += 10) {
        await Promise.all(files.slice(offset, offset + 10).map(file => file.delete({ignoreNotFound: true})));
      }
      // Confirm both stores are empty on a subsequent page before finishing.
      return objects.length === 0 && files.length === 0;
    },
  };
}
module.exports = {storageAdapter};
