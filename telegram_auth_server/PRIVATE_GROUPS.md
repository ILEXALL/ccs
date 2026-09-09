# Private group discovery and join requests

Deploy the updated `api/push-notification.js`, the new `api/private-groups.js`
and `lib/private-groups.js` with the existing telegram_auth_server Vercel project.
Deploy the root `firestore.rules` before distributing the updated Flutter app.
The endpoint uses the existing FIREBASE_SERVICE_ACCOUNT_JSON configuration.
No separate migration or additional Firestore index is required. New groups save
the creator's profile country as `countryCode`. On first discovery, legacy groups
without a country are assigned the current owner's country transactionally. This
is an approximation because historical creation countries were not recorded.
Once assigned, the group's country remains fixed when its owner moves.

Active users see private groups only from their profile country. Public group
tiles are filtered by the same server-provided visible IDs. Profile changes
refresh the directory. Only admins may select another country using the Groups
dropdown; moderators follow their profile country. The server ignores non-admin
country overrides and rejects cross-country join requests. Existing membership
is preserved when a user changes country; this is a directory filter, not removal
from previously joined groups. The
directory endpoint never returns member identities or message previews.
Members open the chat normally. Nonmembers can submit one request for the
lifetime of that group, including after rejection or later leaving the group.
Only the current group owner can accept or reject pending requests. Acceptance,
membership changes, and the decision notification are committed atomically.
Pending request records are intentionally permanent and server-only.

Requests create an in-app notification atomically. The app also asks the existing
push endpoint to send an FCM notification, respecting notification preferences
and deduplicating retries. A push/network failure does not lose the in-app request.
Owners open the notification or use the Join requests button in the directory.

Admins, moderators, and existing global moderators can inspect private messages
without joining. Monitoring hides the composer, attachments, reactions, settings,
and message actions and does not write read receipts. Firestore still requires
membership for sending messages. Staff who are already members chat normally.

Validation:

    node --test telegram_auth_server/lib/private-groups.test.js
    dart analyze lib/main.dart

The backend tests use an in-memory transaction harness, not the Firestore
emulator. Before release, verify on a test Firebase project with an owner, a
nonmember and a moderator: discovery, single request, accept/reject notification
navigation, denied nonmember message reads/writes, and moderator read-only access.
Also verify push delivery on a device; this cannot be validated offline.
