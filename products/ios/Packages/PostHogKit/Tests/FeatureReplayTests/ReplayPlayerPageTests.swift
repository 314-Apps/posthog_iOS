import Foundation
import Testing

@testable import FeatureReplay

/// The player page is a built artifact committed into the tree. Nothing else
/// checks it, and a missing or stale one fails only at runtime, as a blank
/// screen where the recording should be.
@Suite struct ReplayPlayerPageTests {
  private var page: String {
    get throws {
      let data = try #require(ReplayPlayerPage.bundled, "the player page is not in the app bundle")
      return try #require(String(data: data, encoding: .utf8))
    }
  }

  @Test func theBundledPageImplementsTheContract() throws {
    let html = try page
    // Reads the config the app injects.
    let readsConfig = html.contains("__posthog_player_config__")
    #expect(readsConfig)
    // Exposes the commands the app calls.
    for method in ["play", "pause", "seek", "setSpeed"] {
      let defined = html.contains(method)
      #expect(defined, "the page must define posthogPlayer.\(method)")
    }
    // Reports back over the channel the app listens on.
    let postsBack = html.contains("posthogPlayer")
    let fetchesBlocks = html.contains("__blocks/")
    #expect(postsBack)
    #expect(fetchesBlocks)
  }

  /// The recording is played on a device belonging to an organization that may
  /// have turned public sharing off. Rewriting recorded asset URLs through a
  /// public proxy would send them off the device anyway.
  @Test func theBundledPageDoesNotRouteAssetsThroughThePublicProxy() throws {
    let usesProxy = try page.contains("ph-proxy.com")
    #expect(!usesProxy)
  }

  /// A page that reaches out for a script or stylesheet renders nothing when
  /// offline, and leaks where it is being viewed when online.
  @Test func theBundledPageIsSelfContained() throws {
    let html = try page
    for external in ["src=\"http", "src='http", "href=\"http", "href='http", "@import url(http"] {
      let found = html.contains(external)
      #expect(!found, "found an external reference: \(external)")
    }
  }

  /// Guards the stub that lets the Swift side compile before the bundle is
  /// built. Shipping it would mean a blank player.
  ///
  /// The comparisons yield booleans rather than the page itself, because a
  /// failure otherwise prints the whole bundle.
  @Test func theBundledPageIsTheRealPlayer() throws {
    let html = try page
    let isStub = html.contains("posthog-ios-player-stub")
    #expect(!isStub, "the stub player is still installed; run `make player`")
    let isBigEnough = html.utf8.count > 100_000
    #expect(isBigEnough, "the real player is far larger than this")
  }
}
