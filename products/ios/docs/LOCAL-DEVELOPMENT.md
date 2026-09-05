# Local development

## Prerequisites

- Xcode 16.4+ (CI pins the exact version in `.github/workflows/ios-ci.yml`)
- `brew install xcodegen swiftlint`
- No Node or Python environment is needed to build the app. Python 3 (stdlib only) runs the API-lock scripts.

## Quickstart against PostHog Cloud

```bash
cd products/ios
make generate
open PostHog.xcodeproj
```

Run the `PostHog` scheme on an iPhone simulator. Pick US or EU on the welcome screen and sign in with your PostHog account — SSO and 2FA are handled by the in-app browser session.

> OAuth note: sign-in works once the first-party iOS OAuth apps are registered per region (see "OAuth app registration" below). Until then, use the local-stack flow with the dev client.

## Against a local stack

1. Start the stack from the repo root: `hogli start` (Django on `http://localhost:8010`), with `OIDC_RSA_PRIVATE_KEY` set in your `.env` (see `docs/published/handbook/engineering/oauth-development-guide.md`).
2. Generate demo data once (signup flow or `generate_demo_data`); it seeds the shared local dev OAuth app, whose redirect list includes `posthog-ios://oauth/callback`. The app's `.dev` region already uses that client id.
3. Debug builds show a **Local dev** region on the welcome screen (compiled in via `POSTHOG_DEV_REGION`); ATS allows plain-HTTP localhost.

The simulator reaches `localhost` directly. On a physical device, use your Mac's LAN IP in `Region.dev` or a tunnel.

## Refreshing the API lock

The Swift client's contract with the backend is the committed `openapi/api-lock.json`.

```bash
make api-lock    # needs the dev stack running; regenerates the lock from the live spec
make check-api   # stackless check CI runs — Swift surface vs the lock
```

Grow the surface by adding the path to `openapi/endpoint-allowlist.json`, running `make api-lock`, then writing the endpoint.

## Push notifications

APNs requires a real device and the backend's APNs sandbox path (`APNS_USE_SANDBOX=1` plus the `APNS_*` settings). Simulator builds skip push registration.

## Tests and lint

```bash
make test             # unit + snapshot tests on the simulator
make lint             # swiftlint + swift format lint --strict
make snapshot-record  # re-record snapshot baselines after intentional visual changes
```

## Troubleshooting

- **`invalid_client` during sign-in** — the region's client id is wrong or the OAuth app is missing; re-check step 2 above.
- **Consent screen appears** — the OAuth app is not marked first-party (staff-only flag); expected for local dev clients.
- **Redirect never returns** — the redirect URI on the OAuth app must be exactly `posthog-ios://oauth/callback`.
- **Stale project after pulling** — `make generate` (the `.xcodeproj` is generated, never committed).
