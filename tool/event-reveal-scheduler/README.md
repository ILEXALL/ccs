# Event reveal notification rollout

Source implementation is complete; it is not enabled by editing the app.

1. Deploy the changed server modules to the main CCS server using the compatible production baseline. Do not deploy the entire local server over production: unrelated strict security changes still exist locally. Apply the visit validation changes to any legacy server that can record visits too.
2. Set a new random `EVENT_REVEAL_WORKER_SECRET` on the main Vercel project and the same secret on this dedicated Cloudflare Worker. Never commit it or reuse the deletion-worker credential.
3. Set `EVENT_REVEAL_NOTIFICATIONS_SINCE` on Vercel to the activation instant as an ISO UTC timestamp. Scheduled reveals older than that are deliberately excluded to avoid a historical broadcast.
4. Deploy this Worker with `ENABLED = "true"`. Its one-minute trigger calls `/api/community?endpoint=event-reveals`. Keep the existing deletion Worker unchanged. No Vercel cron-plan change is needed.
5. Verify the endpoint rejects missing credentials, Worker invocations succeed, and a controlled public event delivers once to an opted-in same-country test account. Confirm a private event and a different-country test account do not receive it; tap the notification on Android and iOS to verify event navigation.

The worker processes approved, unexpired public events with an explicit scheduled `showOnMapAt`. Events with no reveal lock already have a creation/approval notification. Delivery respects `newSpotNotifications`, bans, deleted users and verified-only event eligibility. Audience uses profile country, not map country filters. Events are rechecked during delivery. No coordinates or group names are put in the push payload.

Recipient scans are paginated with durable checkpoints and shared leases. Per-user delivery keys use the existing push delivery deduplication. A retry resumes interrupted pages; changing the reveal date does not send the same event twice. Large audiences may take additional scheduled runs. As with existing push delivery, OS/network delays apply and delivery across an external FCM call cannot promise exactly-once behavior after a process crash.

Spot visits require an unexpired, fresh live-sharing document even when a GPS fix is posted directly. Recreating sharing resets the five-minute session. Visit history/status and midnight reset use server time in Europe/Riga. Daily status is exposed only to the authenticated account through the existing spot-visit endpoint, without new client Firestore permissions.

## Five-hour reminder extension (22 October 2026)

The handler now calls `dispatchEventNotifications`, which processes both the
five-hour reminder and location reveal. The existing Worker URL, secret and
one-minute schedule are retained. Both audiences use the user's profile country,
not spot filters, and paginate all user documents with durable cursors. Public,
approved, unexpired events only; preference, ban and verified-only checks remain.

Reminders become due at startsAt minus five hours and catch up until startsAt.
Each start time has its own reminder delivery key. Reveal keys remain event-based.
Old app requests use the same dispatcher and keys; their supplied audience is ignored.
No staff app session is required once the main handler is deployed. Scheduling is
minute-granularity; recipient batches and FCM/device delivery can add delay.

Compatibility backend deployed READY: `dpl_CTQxQigbabWgaNangBjpKEnNM8Bn`.
Rollback: `dpl_CP9TJPDKmSkwVwiXk6hTBhqG1mpJ`.
Main scheduler deployment READY: `dpl_CaMJKCf4bScrpqMf3i48X5rQwdej`.
Main rollback: `dpl_Dg6bq1P2RFYqDx2TYsiM9v96D9MK`.
Production alias was re-read and verified. Unauthenticated scheduler requests return 401.
Observed the existing Cloudflare minute cron after deployment (event timestamp
1792617033870): outcome ok, no exceptions, result ok=true, processed=0, busy=false.
No eligible event recipients were processed during this verification.
Targeted tests: 9 scheduler tests (including >600 recipients and retries) and 15
notification regression tests passed. Real-device delivery has not been exercised.
