import Foundation
import Testing
import WebKit

@testable import FeatureReplay

/// A replayed page is real HTML pointing at the hosts the recording came from,
/// so without this block the web view would fetch those assets and tell those
/// hosts the recording is being watched.
@MainActor
@Suite struct ReplayNetworkBlockTests {
  @Test func theRuleBlocksEveryWebRequest() throws {
    let rules = try #require(
      JSONSerialization.jsonObject(with: Data(ReplayNetworkBlock.rules.utf8)) as? [[String: Any]]
    )
    let rule = try #require(rules.first)
    #expect(rules.count == 1)
    #expect((rule["trigger"] as? [String: Any])?["url-filter"] as? String == "^https?://")
    #expect((rule["action"] as? [String: Any])?["type"] as? String == "block")
  }

  /// WebKit rejects a malformed list at compile time, and a rejected list means
  /// the page never loads, so this proves the rule is one WebKit accepts.
  @Test func webKitAcceptsTheRule() async throws {
    let list = await ReplayNetworkBlock.compile()
    #expect(list != nil)
    if let store = WKContentRuleListStore.default() {
      try? await store.removeContentRuleList(forIdentifier: ReplayNetworkBlock.identifier)
    }
  }

  /// The player's own data arrives over its private scheme, which the rule must
  /// not match or nothing would load at all.
  @Test func theRuleLeavesThePlayersOwnSchemeAlone() {
    #expect(!ReplayBlockSchemeHandler.pageURL.absoluteString.hasPrefix("http"))
  }
}
