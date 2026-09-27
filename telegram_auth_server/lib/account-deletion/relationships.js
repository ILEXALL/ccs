// Native Firestore indexes are maintained on every write, including legacy
// clients. No client-maintained backlink collection is trusted for deletion.
function dependentQueries(path) {
  const [root, id, extra] = path.split('/');
  if (extra || !['spots', 'forum_topics'].includes(root)) return [];
  const fields = root === 'spots' ? ['spotId', 'temporarySpotId'] : ['topicId', 'forumTopicId'];
  const roots = root === 'spots'
    ? ['forum_topics', 'spot_reviews', 'spot_likes', 'spot_comment_daily_counts', 'spot_visit_records', 'weekly_visit_records']
    : ['forum_publications'];
  const queries = roots.flatMap(collection => fields.map(field => ({collection, field, value: id})));
  for (const collection of ['user_notifications', 'admin_notifications', 'meet_notifications', 'friend_location_notifications', 'push_deliveries']) {
    for (const field of fields) {
      queries.push({collection, field, value: id}, {collection, field: `data.${field}`, value: id});
    }
  }
  if (root === 'spots') queries.push({collection: 'spot_links', group: true, field: 'spotId', value: id});
  return queries.map(query => ({kind: 'dependents', path, ...query}));
}
module.exports = {dependentQueries};
