# PostHog for iOS

The native Swift/SwiftUI PostHog client: dashboards and insights, feature flag control, and (in later phases) inbox, error tracking, session replay, and Max AI — against PostHog Cloud US/EU.

- Architecture and tree rules: [AGENTS.md](AGENTS.md)
- Getting it running: [docs/LOCAL-DEVELOPMENT.md](docs/LOCAL-DEVELOPMENT.md)
- Releasing: [docs/RELEASE.md](docs/RELEASE.md)

## Quickstart

```bash
brew install xcodegen swiftlint
cd products/ios
make generate
open PostHog.xcodeproj
```

Select the `PostHog` scheme and an iPhone simulator, then run. Debug builds default to PostHog Cloud US; see [docs/LOCAL-DEVELOPMENT.md](docs/LOCAL-DEVELOPMENT.md) to point at a local `hogli start` stack.
