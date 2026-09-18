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

## Visit achievements

- Foreground live sharing and the blue GPS button submit nearby visible public spot IDs and a fresh GPS fix to the existing authenticated /api/spot-visit endpoint.
- The server checks the user, spot access, a 100-metre radius, reported accuracy at most 100 metres, timestamp age at most 150 seconds, and the mock-location flag. Legacy clients can still use a valid stored live-location sample.
- New records use a deterministic user/spot key, independent of date. Only one verified record per spot contributes to Visit achievements. Older daily observed records are excluded from achievement progress.
- Raw GPS coordinates are used for proximity checking but are not copied into visit records. Visit records remain server-only under existing default-deny rules.
- Unique visits unlock tiers at 1, 10, 25, 50 and 100 spots. Existing deterministic achievement award IDs prevent duplicate XP, including retries after a partially failed request.
- Device GPS is not tamper-proof; this is proximity validation, not proof against a modified client. Native background uploads alone do not invoke the achievement endpoint.
- Deploy the backend and rebuild the app. No new Vercel function or Firestore index is required.

## Verification

Tests cover proximity, stale/mock/inaccurate fixes, GPS without live sharing, lifetime deduplication across days, access restrictions and repeated achievement awards. Real-device notification delivery and GPS interaction still require a device check.
