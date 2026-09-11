# Group temporary spots rollout

Public remains the default. Members may select up to eight joined groups. Private and public groups use the same membership checks. Group events appear in Upcoming in cyan with names/avatars. The matching forum topic carries the identical immutable audience. Member notifications are deduplicated across overlapping groups and respect the existing new-spot notification preference and device permissions.

## Required deployment order

1. Run `node scripts/migrate-spot-topic-visibility.cjs` from `telegram_auth_server` using the intended Firebase credentials and inspect the dry-run counts. Run again with `--apply` to mark legacy spots and forum topics public. It refuses records with group IDs but no visibility. It never changes already-classified records.
2. Deploy `firestore.indexes.json` and wait for new indexes to become ready.
3. Deploy both push-notification endpoints and the moderation backend, including the updated `lib/spot-review.js`.
4. Release the updated app and deploy `firestore.rules` together. Require the updated app version through the existing minimum-version setting. Old clients use unscoped public queries, which the new privacy rules correctly reject once private records exist.
5. Verify with two member accounts and one outsider: create a pending event, approve it, check Upcoming and forum, check one bell/push per member, leave the group, and confirm direct links are denied. Admins and assigned moderators retain their existing review access.

No migration or deployment was performed by Codex. The local emulator covers database access and publication; actual FCM delivery and device photo rendering need a device smoke test.

Group membership is checked live in rules. Approved group indexes contain only spot IDs and a publication flag. Pending spots/topics are committed atomically, and moderation publishes the event/topic/indexes atomically. Changing a published event's audience is intentionally unsupported; normal edits preserve it.

Photos continue to use the application's existing R2 media URLs. Database membership checks protect the event/topic records; a copied media URL is not an authenticated, expiring media link.
