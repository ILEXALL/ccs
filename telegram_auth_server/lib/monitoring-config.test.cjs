const test = require('node:test');
const assert = require('node:assert/strict');
const {monitoringConfig} = require('./monitoring-config');
test('existing Firebase account is a fallback without a duplicate secret', () => {
  const result = monitoringConfig({FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({project_id:'demo',private_key:'line1\\nline2'})});
  assert.equal(result.projectId,'demo');
  assert.equal(result.credentials.private_key,'line1\nline2');
});
test('dedicated monitoring credentials take precedence', () => {
  const result = monitoringConfig({GOOGLE_SERVICE_ACCOUNT_JSON_BASE64:Buffer.from(JSON.stringify({project_id:'monitoring'})).toString('base64'),FIREBASE_SERVICE_ACCOUNT_JSON:JSON.stringify({project_id:'fallback'}),GOOGLE_CLOUD_PROJECT_ID:' target '});
  assert.equal(result.credentials.project_id,'monitoring');
  assert.equal(result.projectId,'target');
});
test('malformed credentials never leak their contents through the error', () => {
  assert.throws(()=>monitoringConfig({GOOGLE_SERVICE_ACCOUNT_JSON:'secret-invalid-json'}), /^Error: Monitoring service account configuration is not valid JSON\.$/);
});
test('missing configuration explains what must be set', () => {
  assert.throws(()=>monitoringConfig({}), /Set GOOGLE_CLOUD_PROJECT_ID/);
});
