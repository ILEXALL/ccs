// Uses existing deployment secrets; never logs or returns their contents.
function monitoringConfig(env = process.env) {
  const raw = (env.GOOGLE_SERVICE_ACCOUNT_JSON || '').trim();
  const encoded = (env.GOOGLE_SERVICE_ACCOUNT_JSON_BASE64 || '').trim();
  const fallback = (env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim();
  let credentials;
  try {
    const json = raw || (encoded ? Buffer.from(encoded, 'base64').toString('utf8') : fallback);
    if (json) credentials = JSON.parse(json);
  } catch {
    throw new Error('Monitoring service account configuration is not valid JSON.');
  }
  if (credentials?.private_key) {
    credentials.private_key = credentials.private_key.replace(/\\n/g, '\n');
  }
  const projectId = (env.GOOGLE_CLOUD_PROJECT_ID || env.GCLOUD_PROJECT ||
    env.GCP_PROJECT || credentials?.project_id || '').trim();
  if (!projectId) throw new Error('Set GOOGLE_CLOUD_PROJECT_ID or a service account containing project_id in this Vercel project.');
  return {credentials, projectId};
}
module.exports = {monitoringConfig};
