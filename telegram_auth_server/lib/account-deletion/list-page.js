// Use the public paginated API: CollectionReference.listDocuments() eagerly
// fetches every page, which is unsuitable for the free-tier worker budget.
function collectionPager({db, credential, emulatorHost = process.env.FIRESTORE_EMULATOR_HOST}) {
  if (emulatorHost && emulatorHost !== '127.0.0.1:18080') throw new Error('Unexpected emulator host');
  return async (collectionPath, pageToken = '') => {
    const origin = emulatorHost ? `http://${emulatorHost}` : 'https://firestore.googleapis.com';
    const url = new URL(`${origin}/v1/projects/${db.projectId}/databases/(default)/documents/${collectionPath.split('/').map(encodeURIComponent).join('/')}`);
    // Persist the page cursor separately from its pending paths, so a larger
    // page saves REST round trips without increasing transaction size or
    // skipping unfinished documents when a worker runs out of time.
    url.searchParams.set('pageSize', '100');
    url.searchParams.set('showMissing', 'true');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const headers = emulatorHost ? {Authorization: 'Bearer owner'} : {Authorization: `Bearer ${(await credential.getAccessToken()).access_token}`};
    const response = await fetch(url, {headers, signal: AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error(`Could not list deletion page: ${response.status}`);
    const page = await response.json();
    return {paths: (page.documents || []).map(doc => doc.name.split('/documents/')[1]), nextPageToken: page.nextPageToken || ''};
  };
}
module.exports = {collectionPager};
