# Server deployment — 11 October 2026

## Production releases

- Main: https://ccs-wine.vercel.app — `dpl_7U4nPKnkb5Q3cGWEufxdghGnEoaD`.
- Legacy: https://ccs-telegram-auth-server.vercel.app — `dpl_ESswZKDTK7KW3kkQ9ozXcuLmKrjK`.
- Cloudflare Worker: `ccs-event-reveal-scheduler`, version `3e49bee8-f26b-4ed0-a36c-08919efedfb0`, enabled with a one-minute cron.
- Reveal activation cutoff: `2026-10-11T15:19:56.443Z`. Earlier scheduled reveals are excluded to avoid historical notifications.

Both deployments were assembled from SHA-1-verified production source baselines, applying only the visit changes and, on the main server, event-reveal dispatch. Existing login/upload behavior and the account-deletion scheduler were preserved. No Firestore rules deployment or private-profile migration was performed.

Visits now require fresh, unexpired live sharing. Authenticated daily visit status is available on both hosts. Public event reveals use a dedicated scheduler credential, country-based eligibility, notification preferences, durable progress and delivery deduplication.

## Verification

- Main staged package: 24 targeted tests passed.
- Legacy staged package: 14 targeted tests passed.
- All eight changed/added staged JavaScript modules passed syntax checks.
- Both deployments reached READY and the production aliases point to the release IDs above.
- Both visit endpoints reject unauthenticated status requests with HTTP 401.
- Main event-reveal endpoint rejects missing scheduler credentials with HTTP 401.
- Observed an actual Cloudflare cron invocation on the enabled version: outcome `ok`, no exceptions, server result `ok: true`, `processed: 0`, `busy: false`.

No event was eligible during that observed run. Actual push delivery and notification-tap navigation on Android/iOS still require a controlled eligible event/device check. The mobile app was not built; the owner will build it.

## Rollback references

Previous main production: `dpl_9ESZWWgpuknjo7WhGmJpbQzvkMSR`.
Previous legacy production: `dpl_HcwtzMAtciRGH89eeUXarDhAeL3Z`.
To pause only reveal dispatch, set this dedicated Worker's ENABLED variable to false and deploy it. Keep the account-deletion Worker unchanged. Preserve the activation cutoff on routine redeployments.
