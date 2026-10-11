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
