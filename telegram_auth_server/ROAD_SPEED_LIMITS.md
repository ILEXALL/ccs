# Road speed limits: TomTom evaluation

Implemented and deployed 19 November 2026. Production deployment dpl_GLP3xvtybY1tzvQLYaxUNYeUhrMN is Ready at https://ccs-wine.vercel.app (deployment https://ccs-70edhbefs-ccs-projects1.vercel.app). TOMTOM_API_KEY Production secret existence was verified by metadata only. GET returns 405; unauthenticated and invalid-token POST requests return 401 with no-store. A successful authenticated TomTom result has not been verified: no signed-in CCS ID token was available. No mobile build was performed. Earlier HERE integration is not used.

## Activation (user actions)

1. Register/sign in at https://my.tomtom.com on the **Freemium** plan. Do not buy a prepaid package, enter a card, upgrade, or enable automatic top-ups. Official pricing currently lists **Snap to Roads API / TomTom Maps: 2,500 free monthly requests**. Freemium blocks further calls at exhaustion. Verify this allowance and product access in your own account.
2. In **API & SDK Keys**, use/create a server key in the project with **legacy Snap to Roads API (TomTom Maps)** access. This implementation calls `https://api.tomtom.com/snapToRoads/1`. Do not select the Orbis private-preview Snap API (currently USA-only).
3. In the existing CCS Vercel project, add the sensitive environment variable **TOMTOM_API_KEY** for the intended environment. Never put it in Flutter, a client build flag, source control, logs or chat. Existing Firebase Admin credentials are reused.
4. Optional lower guards: `TOMTOM_SPEED_LIMIT_DAILY_BUDGET` defaults to **1000**; `TOMTOM_SPEED_LIMIT_MONTHLY_BUDGET` defaults to **2500** and is capped at 2500. Zero disables provider spending. Counters use UTC calendar dates and count attempted calls; they cannot know usage from other projects/keys or the provider's billing reset. TomTom's Freemium account is the final quota enforcement.
5. Publish the pending location-provider paragraph in `docs/PRIVACY-POLICY-PUBLICATION-UPDATE.txt`, and review the app-store privacy disclosure for this added recipient before release. No public privacy page was changed here.
6. Redeploy the existing Vercel backend, then build the app yourself. No Firestore rules/index deployment is needed for this feature; server-only counters use the existing default-deny rules and Admin SDK. Earlier comment-reaction rules are a separate change.
7. Test authenticated Follow on actual roads with a passenger car. Confirm local signs versus returned limits on representative roads in every intended market, particularly Russia; verify credential entitlement and regional access. Do not interpret a successful basemap or routing response as proof of speed-limit completeness.

## Contract and behavior

Authenticated `POST /api/road-speed-limit` receives `{points:[{lat,lng,at,speed,accuracy,speedAccuracy,heading,headingAccuracy,mocked}]}`. Three to twelve recent, ordered GPS samples, no older than 30 seconds; newest no older than five seconds. At least two seconds of history is required. Poor accuracy, mocked fixes, implausible jumps, or stationary/uncertain heading yield unavailable. Firebase ID tokens are verified with revocation checks; missing/deleted/banned profiles are denied.

Only coordinates, headings and ISO timestamps are forwarded to TomTom in a POST body. Request parameters specify PassengerCar, metric units, 20m offroad margin and projected points, route confidence, road ID and speedLimits. No average speed profile is requested. The newest projected point selects the road element; the last three matches must be Matched, within 10m of GPS, with confidence at least .95 and consistent travel direction. This reduces wrong-road matches but cannot prove that every parallel-road ambiguity has been detected.

Only a finite positive Maximum speed limit is accepted (kmph or converted mph). Recommended, missing, unknown units, explicit conditional metadata, unlimited/sentinel values, weak matches, reversed travel and malformed results stay unavailable. TomTom documents vehicle/time filtering of speedLimits. This API does not expose every weather/variable-sign condition separately: we cannot independently validate those conditions or promise real-time temporary-sign data. No national legal defaults are invented.

The app shows raw fresh GPS speed independently of road-limit availability. It highlights overspeed only when both a valid limit and fresh good GPS are present. A limit expires at sample time +12s, and is discarded as soon as a new fix moves more than 10m from that sample or changes heading by more than 15 degrees. Conservative validation can produce gaps between readings, especially at driving speed; no last-known limit is carried down another road. Stops do not generate requests. Follow exit, app background, hidden map and disposal cancel the app's pending HTTP request and discard buffered samples/results; an already sent upstream request may still finish.

Maximum one request per driver per five seconds; shared durable pacing allows at most four provider calls per second. The app backs off 15–300 seconds for unavailable responses and 30 seconds on transport failure. Backend upstream requests time out after four seconds; the client transport closes after six seconds (plus bounded token retrieval). Exact duplicate requests reuse a bounded five-second in-memory result. No disk map cache, trace database or indefinite cached limit is created.

At the five-second maximum cadence, 2,500 calls permit about **3.47 hours total per month across the project**. There are also existing Firebase/Vercel operations for authentication and quota counters. Freemium is suitable for evaluation; it is not an unlimited free service for sustained multi-driver navigation. No paid services were purchased or enabled.

## Coverage and updates

Calls use TomTom's hosted data rather than a bundled speed-limit database, so later provider updates do not require an app release. The time from a changed physical sign to provider publication is not verified or guaranteed. Full speed-limit coverage for every European road and the whole of Russia is **not verified**. This requirement remains an evaluation item, not a delivered coverage guarantee.

## Data handling

The feature buffers only the recent trace in app memory while Follow is active. CCS backend code does not log request bodies, upstream URLs/keys or precise traces and writes only account quota times/counters to Firestore. A bounded duplicate-response cache may hold the last matched coordinates for five seconds. TomTom receives coordinates, headings and sample times via CCS's backend, without the Firebase token or account ID. Infrastructure/provider logging and retention are governed separately by their configurations/policies; no claim of zero third-party retention is made.

## Verification and references

Run `node --test telegram_auth_server/test/road-speed-limit.test.cjs` from the repository root. Flutter tests: `test/road_speed_test.dart` and `test/road_speed_controller_test.dart`. Fixtures are synthetic and do not establish live access or country coverage.

- Contract: https://docs.tomtom.com/snap-to-roads-api/documentation/snap-to-roads-api/synchronous-snap-to-roads
- Legacy product/access: https://docs.tomtom.com/snap-to-roads-api/documentation/product-information/introduction
- Pricing: https://docs.tomtom.com/pricing
- Freemium no-card/blocking: https://docs.tomtom.com/platform/documentation/my-tomtom/plans-balance-and-top-ups
- Key setup: https://docs.tomtom.com/platform/documentation/my-tomtom/how-to-get-a-tomtom-api-key
- Orbis restriction: https://docs.tomtom.com/snap-to-roads-api/documentation/tomtom-orbis-maps/v1/product-information/introduction
