# Spot presence and visit observations

Local implementation on alex-ui. No deployment, rule publication or XP activation.

## Map

- Nearby radius is 100 metres, without rounding distance to an integer.
- At zoom 14 and above, visible shared-location people at one spot become a count marker. Their separate car markers are hidden; the current user's navigation marker remains.
- One person is assigned to the nearest eligible visible spot. Exact ties use the spot ID to avoid double counting.
- Only already authorized live locations are used. A private share never becomes public because it is inside a cluster. Counts may differ by viewer.
- Samples older than 150 seconds, expired shares and future/missing timestamps are excluded. Updates follow existing GPS uploads and the map's refresh timer, not instantaneous continuous tracking.
- The spot card opens the nearby people list. The list refreshes every five seconds and opens profiles through the existing profile navigation.
- Existing friend arrival notifications remain at 200 metres and five minutes. This change does not modify that separate rule.

## Visit record

- After foreground Dart live-location upload, the client nominates the nearest eligible public spot. The server authenticates the user and re-reads their stored live location and spot.
- POST /api/spot-visit accepts only spotId. Request coordinates, user ID and claimed completion are not used.
- Reject stale/expired/mock positions, reported accuracy worse than 100 metres, unavailable spots and insufficient verified-only access. Group-private spots are not recorded by this first implementation.
- spot_visit_records stores one observation per user/spot/Riga calendar day. No raw coordinates are copied. Records are not a public attendance history.
- Repeated requests do not create another record. No XP or weekly progress is awarded. Status observed means a server-checked proximity observation, NOT proof against GPS spoofing.
- The existing client-writable live_locations document is not a fraud-proof source. App/device attestation and movement checks are still required before using visits for XP. A missing legacy accuracy field is permitted for compatibility, so it cannot certify GPS precision.
- Native background uploads are not wired to this endpoint. Foreground sharing and a fresh sample are needed; simply granting device location permission does not activate public sharing or visit recording.
- Deploy the new endpoint on the ccs-telegram-auth-server host together with the client build. Existing Firestore default-deny rules keep the new observation collection inaccessible to direct clients; Admin SDK writes it.

## Verification

Node tests cover the 100m boundary, duplicates, privacy/eligibility, stale samples, Riga dates and endpoint authentication. Flutter tests cover grouping, leaving, overlapping radii, invalid samples, a 320px counter/list in three languages and profile callbacks. Real-device GPS and concurrent Firestore transactions still require emulator/device testing before rollout.
