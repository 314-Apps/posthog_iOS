# PostHog for iOS

Native Swift/SwiftUI client for PostHog. This tree is an app-only product: no Django backend, no frontend/ scene, no Node toolchain. The root monorepo conventions for Python and TypeScript do not apply here.

## Toolchain overrides

| Concern | Root monorepo | This tree |
| --- | --- | --- |
| Language | Python / TypeScript | Swift 6 (strict concurrency) |
| Lint | ruff / oxlint | SwiftLint (`.swiftlint.yml`) |
| Format | ruff format / oxfmt | `swift format` (toolchain-bundled; `.swift-format`) |
| Tests | pytest / Jest | swift-testing via `xcodebuild test` |
| Project | — | XcodeGen (`project.yml`); the `.xcodeproj` is generated and gitignored |
| UI | Lemon/quill | SwiftUI + `PostHogDesignSystem` |

Do not import monorepo idioms (kea, Lemon, Django patterns) into this tree, and do not copy Swift idioms out of it into the web app.

## Layout and layering

All code lives in one local SPM package, `Packages/PostHogKit`, split into targets. Imports flow strictly downward; a target may depend only on targets above it in this list:

1. `PostHogFoundation` — JSONValue, logging, formatting. Depends on nothing.
2. `PostHogAPI` — transport, interceptors, endpoints, SSE, query polling, disk cache.
3. `PostHogQueries` — the `DataQuery` union + response models.
4. `PostHogAuth` — PKCE, Keychain, TokenBroker, AuthService.
5. `PostHogDesignSystem` — tokens, components, `InsightRenderer`.
6. `PostHogDrilldown` — the shared drill-down surfaces (people behind a number, query provenance). A layer rather than a feature precisely so several features can present it.
7. `Feature*` targets — one per product surface. Features never import each other.
8. `AppShell` — tabs, Router, deep links, SessionStore, DI. The app target depends only on this.

The `App/` directory is a thin shell: entry point, entitlements, Info.plist keys, assets, xcconfigs. Business logic in `App/` is a defect.

## API surface rules

- Target `/api/projects/{project_id}/…` only. `/api/environments/` is deprecated (sunset 2026-07-31); `scripts/check-api-drift.py` fails CI if it appears.
- The endpoint surface is hand-written and confined to `openapi/endpoint-allowlist.json`. The committed `openapi/api-lock.json` is the contract snapshot; refresh it with `make api-lock` (needs a running dev stack). If the allowlist grows past ~50–60 paths, revisit generated clients (swift-openapi-generator) — that is the tripwire.
- Query kinds are modeled in `PostHogQueries.DataQuery` as an enum over the `kind` discriminator. Unknown kinds must decode to `.unknown(kind:raw:)` — never throw. Unmodeled fields ride through as `JSONValue`; re-encoding a saved insight's query must not strip fields.

## Auth rules

- OAuth authorization-code + PKCE (S256) via `ASWebAuthenticationSession`; redirect scheme `posthog-ios://oauth/callback`. Never reuse the RN app's `posthog://` scheme.
- Refresh-error taxonomy is load-bearing (ported from `products/desktop/apps/mobile/src/features/auth/lib/oauth.ts`): only HTTP 401/403, or a 400 whose body `error` is `invalid_grant`/`invalid_token`, signs the user out. Other 400s (e.g. `invalid_client`) are config bugs and must keep the session.
- Tokens live in the Keychain only, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. All refresh goes through the `TokenBroker` actor (single-flight).

## Commands

```bash
make generate         # xcodegen → PostHog.xcodeproj
make build            # xcodebuild build for the iPhone simulator
make test             # unit + snapshot tests (simulator)
make lint             # swiftlint + swift format lint --strict
make snapshot-record  # re-record snapshot baselines
make api-lock         # refresh openapi/api-lock.json (needs `hogli start` stack)
```

## Stepping outside this tree

Only three sanctioned reasons:

1. The user asks.
2. A Django API this client calls must change — that is a monorepo-side change (invoke `/improving-drf-endpoints`, `/django-migrations` as usual, separate PR).
3. The fixed list of root files that reference this tree: `.github/workflows/ios-*.yml`, the `ios:*` command entries in `hogli.yaml`, the `pnpm-workspace.yaml` negative glob, `.dockerignore`, `.oxfmtrc.json` excludes, and the `changes` filters in `ci-frontend.yml` / `ci-backend.yml` / `ci-storybook.yml` / `.depot/workflows/ci-backend.yml`.

Never let anything in this tree alter the root pnpm lockfile, pyproject, or Django settings.
