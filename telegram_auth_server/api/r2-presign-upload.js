const {S3Client, PutObjectCommand} = require('@aws-sdk/client-s3');
const {getSignedUrl} = require('@aws-sdk/s3-request-presigner');
const {admin, db} = require('../lib/firebase-admin');
const {createUploadHandler} = require('../lib/media-uploads');

module.exports = createUploadHandler({auth: admin.auth(), db, sign: async ({key, contentType, cacheControl}) => {
  for (const name of ['R2_ENDPOINT', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET_NAME', 'R2_PUBLIC_BASE_URL']) {
    if (!process.env[name]) throw new Error('Missing storage configuration');
  }
  const client = new S3Client({region: 'auto', endpoint: process.env.R2_ENDPOINT,
    credentials: {accessKeyId: process.env.R2_ACCESS_KEY_ID, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY}});
  const command = new PutObjectCommand({Bucket: process.env.R2_BUCKET_NAME, Key: key,
    ContentType: contentType, CacheControl: cacheControl});
  const uploadUrl = await getSignedUrl(client, command, {expiresIn: 300});
  return {uploadUrl, publicUrl: `${process.env.R2_PUBLIC_BASE_URL.replace(/\/+$/, '')}/${key}`};
}});
