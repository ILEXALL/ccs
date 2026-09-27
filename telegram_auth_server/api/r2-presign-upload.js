import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import firebase from '../lib/firebase-admin.js';

const allowedPrefixes = ["spots/", "users/", "garage/"];
const allowedContentTypes = ["image/jpeg", "image/png", "image/webp"];
const defaultCacheControl = "public, max-age=31536000, immutable";

function cleanPath(value) {
  return String(value || "")
    .trim()
    .replace(/^\/+/, "")
    .replace(/\.\./g, "");
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  try {
    const bearer = req.headers.authorization || '';
    if (!bearer.startsWith('Bearer ')) return res.status(401).json({error: 'Sign in required'});
    let token;
    try { token = await firebase.admin.auth().verifyIdToken(bearer.slice(7), true); }
    catch (_) { return res.status(401).json({error: 'Sign in required'}); }
    if ((await firebase.db.collection('account_deletions').doc(token.uid).get()).exists) {
      return res.status(403).json({error: 'Account deletion in progress'});
    }
    const path = cleanPath(req.body?.path);
    const contentType = String(req.body?.contentType || "").trim();
    const cacheControl = String(
      req.body?.cacheControl || defaultCacheControl
    ).trim();

    if (!path) {
      return res.status(400).json({ error: "Missing path" });
    }

    if (!allowedPrefixes.some((prefix) => path.startsWith(prefix))) {
      return res.status(400).json({ error: "Invalid upload path" });
    }
    const [root, owner] = path.split('/');
    if (['users', 'garage'].includes(root) && owner !== token.uid) {
      return res.status(403).json({error: 'Upload path belongs to another account'});
    }
    if (root === 'spots') {
      const [spot, actor] = await Promise.all([
        firebase.db.collection('spots').doc(owner).get(),
        firebase.db.collection('users').doc(token.uid).get(),
      ]);
      if (spot.exists && spot.data().addedByUid !== token.uid && spot.data().ownerUid !== token.uid && actor.data()?.role !== 'admin') {
        return res.status(403).json({error: 'No permission to upload to this spot'});
      }
    }

    if (!allowedContentTypes.includes(contentType)) {
      return res.status(400).json({ error: "Invalid content type" });
    }

    const client = new S3Client({
      region: "auto",
      endpoint: process.env.R2_ENDPOINT,
      credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
      },
    });

    const command = new PutObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME,
      Key: path,
      ContentType: contentType,
      CacheControl: cacheControl,
    });

    const uploadUrl = await getSignedUrl(client, command, {
      expiresIn: 300,
    });

    const publicBaseUrl = String(process.env.R2_PUBLIC_BASE_URL || "").replace(
      /\/+$/,
      ""
    );

    return res.status(200).json({
      uploadUrl,
      publicUrl: `${publicBaseUrl}/${path}`,
      key: path,
      cacheControl,
    });
  } catch (error) {
    return res.status(500).json({
      error: "Could not create R2 upload URL",
      details: String(error?.message || error),
    });
  }
}
