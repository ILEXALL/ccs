const {S3Client, ListObjectsV2Command, DeleteObjectsCommand} = require('@aws-sdk/client-s3');

function storageAdapter(env = process.env, {client: suppliedClient} = {}) {
  for (const key of ['R2_ENDPOINT', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET_NAME']) {
    if (!env[key]) throw new Error(`Deletion storage configuration missing: ${key}`);
  }
  const client = suppliedClient || new S3Client({region: 'auto', endpoint: env.R2_ENDPOINT,
    credentials: {accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY}});
  return {
    async deleteObject(key) {
      if (typeof key !== 'string' || !/^(users|garage|spots)\/[A-Za-z0-9_-]+\/[A-Za-z0-9_./-]+$/.test(key) ||
          key.split('/').some(part => !part || part === '.' || part === '..')) throw new Error('Unsafe storage key');
      const result = await client.send(new DeleteObjectsCommand({Bucket: env.R2_BUCKET_NAME,
        Delete: {Objects: [{Key: key}], Quiet: true}}));
      if (result.Errors?.length) throw new Error('Some media objects could not be deleted');
    },
    // Always restart at the prefix beginning: objects disappear after each batch.
    async deletePrefixPage(prefix) {
      if (!/^(users|garage|spots)\/[A-Za-z0-9_-]+\/$/.test(prefix)) throw new Error('Unsafe storage prefix');
      const page = await client.send(new ListObjectsV2Command({Bucket: env.R2_BUCKET_NAME, Prefix: prefix, MaxKeys: 500}));
      const objects = (page.Contents || []).map(item => ({Key: item.Key}));
      if (!objects.length) return true;
      const result = await client.send(new DeleteObjectsCommand({Bucket: env.R2_BUCKET_NAME, Delete: {Objects: objects, Quiet: true}}));
      if (result.Errors?.length) throw new Error('Some media objects could not be deleted');
      return false;
    },
  };
}
module.exports = {storageAdapter};
