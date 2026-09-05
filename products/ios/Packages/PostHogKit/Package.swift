// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PostHogKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17)],
  products: [
    .library(name: "AppShell", targets: ["AppShell"]),
    // Consumed by the widget extension only — keep this surface tiny.
    .library(name: "PostHogFoundation", targets: ["PostHogFoundation"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    // Dogfooding our own SDK is table stakes for a first-party client.
    .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0"),
  ],
  targets: [
    // MARK: Core layers (imports flow strictly downward — see products/ios/AGENTS.md)
    .target(name: "PostHogFoundation"),
    .target(
      name: "PostHogAPI",
      dependencies: ["PostHogFoundation"]
    ),
    .target(
      name: "PostHogQueries",
      dependencies: ["PostHogFoundation", "PostHogAPI"]
    ),
    .target(
      name: "PostHogAuth",
      dependencies: ["PostHogFoundation", "PostHogAPI"]
    ),
    .target(
      name: "PostHogDesignSystem",
      dependencies: ["PostHogFoundation", "PostHogQueries"]
    ),
    // Shared drill-down surfaces: who is behind this number, and where did it
    // come from. Sits below the features so any of them can present it.
    .target(
      name: "PostHogDrilldown",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),

    // MARK: Features (never import each other)
    .target(
      name: "FeatureDashboards",
      dependencies: [
        "PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem", "PostHogDrilldown",
      ]
    ),
    .target(
      name: "FeatureInsights",
      dependencies: [
        "PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem", "PostHogDrilldown",
      ]
    ),
    .target(
      name: "FeatureFlags",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureSettings",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogAuth", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureInbox",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureErrors",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureLive",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureReplay",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"],
      // Built from products/ios/player and committed, because iOS CI checks out
      // only this tree and cannot rebuild it.
      resources: [.copy("Resources/player.html")]
    ),
    .target(
      name: "FeatureMax",
      dependencies: [
        "PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem", "PostHogDrilldown",
      ]
    ),
    .target(
      name: "FeatureExperiments",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureSurveys",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureWeb",
      dependencies: [
        "PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem", "PostHogDrilldown",
      ]
    ),
    .target(
      name: "FeaturePeople",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureSQL",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),
    .target(
      name: "FeatureActivity",
      dependencies: ["PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogDesignSystem"]
    ),

    // MARK: Shell
    .target(
      name: "AppShell",
      dependencies: [
        "PostHogFoundation", "PostHogAPI", "PostHogQueries", "PostHogAuth", "PostHogDesignSystem",
        "PostHogDrilldown",
        "FeatureDashboards", "FeatureInsights", "FeatureFlags", "FeatureSettings",
        "FeatureInbox", "FeatureErrors", "FeatureLive", "FeatureReplay", "FeatureMax",
        "FeatureExperiments", "FeatureSurveys", "FeatureWeb", "FeaturePeople",
        "FeatureSQL", "FeatureActivity",
        .product(name: "PostHog", package: "posthog-ios"),
      ]
    ),

    // MARK: Tests
    .target(
      name: "PostHogTestSupport",
      dependencies: ["PostHogAPI"],
      path: "Tests/PostHogTestSupport"
    ),
    .testTarget(name: "PostHogFoundationTests", dependencies: ["PostHogFoundation"]),
    .testTarget(name: "PostHogAPITests", dependencies: ["PostHogAPI", "PostHogTestSupport"]),
    .testTarget(
      name: "PostHogQueriesTests",
      dependencies: ["PostHogQueries", "PostHogTestSupport"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "PostHogAuthTests", dependencies: ["PostHogAuth", "PostHogTestSupport"]),
    .testTarget(name: "AppShellTests", dependencies: ["AppShell"]),
    .testTarget(name: "FeatureInboxTests", dependencies: ["FeatureInbox", "PostHogTestSupport"]),
    .testTarget(name: "FeatureErrorsTests", dependencies: ["FeatureErrors", "PostHogTestSupport"]),
    .testTarget(name: "FeatureLiveTests", dependencies: ["FeatureLive", "PostHogTestSupport"]),
    .testTarget(name: "FeatureInsightsTests", dependencies: ["FeatureInsights", "PostHogTestSupport"]),
    .testTarget(name: "FeatureReplayTests", dependencies: ["FeatureReplay", "PostHogTestSupport"]),
    .testTarget(name: "FeatureMaxTests", dependencies: ["FeatureMax", "PostHogTestSupport"]),
    .testTarget(
      name: "FeatureExperimentsTests",
      dependencies: ["FeatureExperiments", "PostHogTestSupport"]
    ),
    .testTarget(name: "FeatureSurveysTests", dependencies: ["FeatureSurveys", "PostHogTestSupport"]),
    .testTarget(name: "FeatureWebTests", dependencies: ["FeatureWeb", "PostHogTestSupport"]),
    .testTarget(name: "FeaturePeopleTests", dependencies: ["FeaturePeople", "PostHogTestSupport"]),
    .testTarget(name: "FeatureSQLTests", dependencies: ["FeatureSQL", "PostHogTestSupport"]),
    .testTarget(name: "FeatureActivityTests", dependencies: ["FeatureActivity", "PostHogTestSupport"]),
    .testTarget(
      name: "PostHogDrilldownTests",
      dependencies: ["PostHogDrilldown", "PostHogTestSupport"]
    ),
    .testTarget(
      name: "DesignSystemSnapshotTests",
      dependencies: [
        "PostHogDesignSystem",
        "PostHogQueries",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
