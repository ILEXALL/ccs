# Groups joining and membership update

Implemented:
- Required trimmed group description, maximum 1,000 characters, in creation UI, creation helper and Firestore create rules. Existing groups are not rewritten.
- Public groups use Join group immediately. Private groups retain owner-approved requests. Both remain country-scoped.
- Public and private labels/icons are distinct; both directory cards and joined group cards show member counts.
- Messaging still requires actual membership. Read-only moderation access never grants permission to send.
- Existing Remove member kicks the member. For public groups they can join again. The owner also has Permanently deny access in the member menu, with confirmation. This removes membership and moderator status and blocks future join requests, public joins and client-side reinvites.
- Public joining is transactional and idempotent and preserves aligned member arrays. Permanent bans are server-controlled.

Apply the updated firestore.rules, deploy Vercel production from telegram_auth_server, then rebuild/install the app. No new index is needed. Vercel remains at 12 API functions. Nothing was deployed or built by Codex.

Validation: 11 Flutter group tests, 19 backend group tests, and 12 real local Firestore-emulator tests passed. The emulator verifies blank/oversized descriptions are denied, multiline descriptions are allowed, non-members/banned members cannot message, and banned members cannot be re-added by a client. Verify the final flows on Android/iOS after deployment.
