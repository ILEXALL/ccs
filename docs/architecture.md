# CCS Flutter architecture

The September 2026 modularization uses the working project as its baseline,
including the uncommitted changes that were already in `lib/main.dart`.
The entry point now delegates to bootstrap; feature code lives in its own libraries.

## Entry points and composition

```text
lib/main.dart
  -> app/bootstrap.dart
       -> configureAppNavigation()
       -> configureAppServices()
       -> existing Firebase, preferences and session initialization
       -> CCSApp
            -> access gates / app shell
```

- `app/bootstrap.dart` preserves the startup sequence and the annotated Firebase
  Messaging background entry point.
- `app/ccs_app.dart` owns the root widget.
- `app/app_shell.dart` owns tabs and app-level lifecycle coordination.
- `app/app_navigation.dart` binds navigation contracts to route implementations.
- `app/app_services.dart` binds spot-sync account lifecycle callbacks.
- `features/auth/data/session_lifecycle.dart` owns the account watcher and logout
  cleanup. It coordinates feature services without importing their screen widgets.
- `app/gates/maintenance_state.dart` provides shared runtime access configuration;
  gates render the corresponding maintenance, version, ban and region screens.

Configure navigation and services before mounting standalone screens. Normal
startup does this in bootstrap. `test/flutter_test_config.dart` performs the same
composition for widget tests. Binding callbacks does not start subscriptions.

## Where code belongs

| Folder | Responsibility |
| --- | --- |
| `app/` | Startup, root widget, navigation composition, gates and shell |
| `core/config/` | Existing backend URLs and application constants |
| `core/firestore/` | Collection references, value parsing, query helpers and read/write instrumentation |
| `core/localization/` | Language preferences, RU/LV dictionaries, translated text and language-aware state |
| `core/location/` | Permission/position helpers and finite-coordinate calculations |
| `core/network/` | HTTP transport and request coalescing |
| `core/platform/` | Native channels, device identity and external link handling |
| `core/theme/` | Theme values, backgrounds and route transitions |
| `shared/` | Shared identity types, media helpers, date formatting and reusable controls |
| `features/auth/` | Sign-in, usernames, account access, preferences and session cleanup |
| `features/profile/` | Own/public profiles, settings, social links and garage |
| `features/friends/` | Relationships, blocking, requests and user search |
| `features/spots/` | Feed, permanent spots, creation, details, comments, reviews and saved spots |
| `features/events/` | Event scheduling, upcoming-event grouping and reminders |
| `features/map/` | Map UI, navigation, markers, live sharing and reports |
| `features/community/` | Chat, groups, global chat, forum and country selection |
| `features/progression/` | XP APIs, visits, ranking, achievements, rewards and feedback |
| `features/notifications/` | Push registration, bell feed, unread counts, badges and freshness |
| `features/partners/` | Partner directory, detail and creation screens |
| `features/moderation/` | Admin/moderator tools, regional access, review leases and debug UI |

Existing standalone modules were relocated, not reimplemented. The generated
`firebase_options.dart` stays at the library root. There are no exports from
`main.dart` and no `part of main.dart` libraries.

Within each feature:

- `models/` contains values, parsing and domain calculations.
- `data/` contains queries, persistence, caches and service operations.
- `controllers/` coordinates screen actions, loading and refreshes.
- `screens/` owns widget lifecycle and screen composition.
- `widgets/` contains reusable visual sections.
- `navigation/`, when present, contains a narrow navigation contract or a
  feature-local route action.

Not every feature needs every directory. Keep related behavior together; do not
create empty layers or move feature-specific helpers into a generic utilities file.

## Translation

Use `CcsText` from `core/localization/ccs_text.dart` for the translated text behavior
previously implemented by the custom class named `Text` in main.dart.
`LanguageReactiveState` keeps computed labels and hints responsive to language
changes without replacing screen state. Ordinary Flutter `Text` remains appropriate
where a component intentionally handles its own translation.

Keep translation keys and existing language behavior stable when changing imports.

## State and lifecycle ownership

The refactor keeps ValueNotifier/ChangeNotifier and existing service behavior.
It does not introduce a new state-management framework or duplicate the global
application state behind another service container.

Feature state is located with its owner. For example:

- Authentication/session identity: `features/auth/data/auth_state.dart`.
- Profile settings and garage: `features/profile/data/profile_state.dart`.
- Spot lists: `features/spots/data/spot_state.dart`.
- Spot feed caches and generation/scope checks: `spot_feed_state.dart`.
- Merging feed snapshots into visible lists: `spot_feed_projection.dart`.
- Firestore feed subscriptions and retries: `spot_sync.dart`.
- Group spot access state: `community/groups/data/group_spot_access.dart`.
- Notification badges: `notifications/data/badge_state.dart`.

Do not start a new listener just because another widget needs an existing value.
Keep cancellation, generation checks and account/country scoping with the service
that already owns the work. Logout and access changes must continue cancelling
those services before stale asynchronous work can affect another account.

Large screens expose typed `*ViewState` contracts to their controllers and content
builders. The screen retains controllers, timers, subscriptions and disposal;
action/content classes do not duplicate that state. Widget inputs have small typed
interfaces so controllers do not import their concrete screen classes.

## Map modules

`MapScreen` composes the map and owns view-state lifecycle. Its behavior is divided
into these controllers:

| Controller | Responsibility |
| --- | --- |
| `map_navigation_controller.dart` | GPS tracking, heading smoothing, camera following and route preview |
| `map_layers_controller.dart` | Spot, report, presence and current-user markers |
| `map_presence_controller.dart` | Live-location subscriptions, visibility and presence grouping |
| `map_sharing_controller.dart` | Remote location publishing, native background service and sharing timers |
| `map_police_controller.dart` | Police report creation, voting and removal |
| `map_sos_controller.dart` | SOS requests, location checks and messaging |
| `map_appearance_controller.dart` | Style preferences, filters and map refresh coordination |

`map_session.dart` defines typed state/action interfaces. Controllers borrow the
screen's state; the screen remains responsible for disposing it. Controller methods
that retain a BuildContext explicitly check the screen/context lifecycle.

Local marker interpolation and remote location publishing remain separate. The
existing live-sharing upload interval remains **60 seconds**, in `map_config.dart`.
Opening the map must not implicitly enable remote location sharing.

## Dependency rules

1. Production code never imports `main.dart`.
2. Core code never imports app or feature code.
3. Shared code never imports feature screens.
4. Features never import the bootstrap, root widget or app shell.
5. Navigation back to an application-level destination uses an injected contract.
6. There must be no import cycles, including cycles through exports.
7. Keep private widget state private. Tests use public domain APIs or typed view
   contracts when testing a screen/controller boundary.

Run the dependency check from the project root:

```sh
dart tool/check_module_boundaries.dart
```

The script has no third-party dependencies and checks missing local libraries,
entry-point imports, layer violations and cycles.

## Verification and migration record

- `modularization-ledger.json` accounts for all **1,198 original declaration
  groups** from main.dart, including renamed declarations and extracted screen
  methods. Its line numbers describe the completed migration snapshot and may
  change with subsequent edits.
- Existing test imports now point directly to their owning modules.
- The unresolved merge conflict in `spot_presence_ui_test.dart` was resolved using
  the existing cross-platform preview-font helper.
- Added navigation-controller regression tests cover angle wrapping, stationary
  GPS drift, moving course updates, invalid coordinates and camera bounds.
- The final full suite passed **237 tests**. Static analysis has no errors;
  pre-existing warnings and informational lints remain.
- The moved-code audit compared 883 non-class declarations at token level,
  allowing identifier renames and formatting. Only bootstrap composition and the
  logout navigation delegation intentionally changed their tokens beyond those
  renames. Screen/controller extraction is also covered by the regression suite.

Useful commands:

```sh
flutter analyze
flutter test --no-pub
dart tool/check_module_boundaries.dart
```

Most files are small, focused modules. Translation dictionaries and several
coherent submission/chat workflows remain around 1,000–1,200 lines. Keep those
transaction and lifecycle sequences together unless a further split introduces a
clear responsibility boundary; a line-count limit alone is not a reason to split.

## Build and deployment

This migration changes Flutter source and tests. It does not change Firestore
rules, indexes, backend functions, database schemas, assets or native configuration.
The existing `intl` and `uuid` imports now have explicit direct dependencies in
`pubspec.yaml`; their resolved package versions are unchanged.
No app binary was built and nothing was deployed during the refactor.

Rebuild the app normally. On a device, smoke-test login/logout, language switching,
GPS permission and map following/manual gestures, live sharing/background resume,
chat/group membership, notifications, profile/ranking and moderation. Automated
tests cannot certify platform permission prompts or real GPS/push delivery.
