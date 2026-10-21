# Releasing PostHog for iOS

## Pipeline

1. **Tag**: `ios-tag.yml` computes `ios-vX.Y.Z` (Z = commits touching `products/ios/` since the `ios-vX.Y` base tag) and pushes it. Trigger it via workflow dispatch, or the `ios-release` label on a merged PR.
2. **Build + TestFlight**: `ios-release.yml` fires on the tag. It stamps versions (`scripts/set-version.sh`; build number = `run_number * 10 + run_attempt`), archives with cloud signing (`-allowProvisioningUpdates` + the App Store Connect API key — no certificate secrets), exports with `destination: upload` straight to TestFlight, creates the GitHub release with the `.ipa` and dSYMs, and uploads dSYMs to PostHog error tracking.
3. **App Store**: promotion to review is manual in App Store Connect for now; `ios-promote.yml` automates it in a later phase.

## Secrets

| Secret | Purpose |
| --- | --- |
| `IOS_ASC_API_KEY_ID` | App Store Connect API key id (App Manager role) |
| `IOS_ASC_API_ISSUER_ID` | ASC issuer id |
| `IOS_ASC_API_KEY_P8` | base64 of the `.p8` private key |
| `APPLE_TEAM_ID` | shared with desktop |
| `IOS_POSTHOG_ERROR_TRACKING_KEY` | dSYM upload |

## Versioning

- Marketing version comes from the tag (`ios-v0.3.14` → `0.3.14`).
- Build number is monotonically increasing per workflow run and unique across re-run attempts, so a failed release re-run never collides with an already-uploaded build.
- `manageAppVersionAndBuildNumber` is off — we own the numbers.

## Capabilities to register (ops, before archives sign)

Cloud signing (`-allowProvisioningUpdates`) can only mint profiles for capabilities that exist on the identifiers in App Store Connect: register the `group.com.posthog.ios` App Group on both `com.posthog.ios` and `com.posthog.ios.widgets`, and enable Push Notifications on `com.posthog.ios`. Simulator builds don't need any of this.

## App Review

The app requires a PostHog account, so every submission carries demo credentials in the review notes (dedicated demo org on US Cloud with seeded data). Keep that project's data fresh before promoting; the "Try the demo" path on the welcome screen uses the same account.
