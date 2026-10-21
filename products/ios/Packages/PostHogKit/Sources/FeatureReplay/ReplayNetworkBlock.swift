import Foundation
import PostHogFoundation
import WebKit

/// Stops the player reaching the network.
///
/// A replayed page is real HTML, so its images, stylesheets and fonts point at
/// the hosts the recording came from. Left alone the web view would fetch them,
/// which tells those hosts that the recording is being watched and from where.
/// Dropping the CORS-proxy plugin is not enough on its own, because that only
/// changes which host the request goes to.
///
/// Everything the player legitimately needs arrives over `posthog-replay`, so
/// blocking every http and https load costs nothing real and cannot be talked
/// around by the page.
@MainActor
enum ReplayNetworkBlock {
  static let identifier = "posthog-replay-offline"

  static let rules = """
    [{"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}}]
    """

  /// Compiles the block, or returns nil when WebKit will not give us one.
  /// The caller must then refuse to load the page: playing a recording without
  /// the block is the leak this exists to prevent.
  static func compile() async -> WKContentRuleList? {
    guard let store = WKContentRuleListStore.default() else {
      PHLog.api.error("no content rule list store, refusing to load the replay player")
      return nil
    }
    do {
      return try await store.compileContentRuleList(
        forIdentifier: identifier,
        encodedContentRuleList: rules
      )
    } catch {
      PHLog.api.error("replay network block failed to compile: \(error)")
      return nil
    }
  }
}
