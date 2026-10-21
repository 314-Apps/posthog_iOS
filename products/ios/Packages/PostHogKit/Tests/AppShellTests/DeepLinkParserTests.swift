import Foundation
import Testing

@testable import AppShell

@Suite struct DeepLinkParserTests {
  @Test func parsesProjectScopedRoutes() throws {
    let dashboard = DeepLinkParser.parse(URL(string: "posthog-ios://project/123/dashboard/45")!)
    #expect(dashboard?.projectID == 123)
    #expect(dashboard?.route == .dashboard(id: 45))

    let insight = DeepLinkParser.parse(URL(string: "posthog-ios://project/123/insights/67")!)
    #expect(insight?.route == .insight(id: 67))

    let flag = DeepLinkParser.parse(URL(string: "posthog-ios://project/123/feature_flags/89")!)
    #expect(flag?.route == .flag(id: 89))
  }

  @Test func parsesProjectlessRoutes() {
    let link = DeepLinkParser.parse(URL(string: "posthog-ios://dashboard/45")!)
    #expect(link?.projectID == nil)
    #expect(link?.route == .dashboard(id: 45))
  }

  @Test func parsesTabLevelLinks() {
    let max = DeepLinkParser.parse(URL(string: "posthog-ios://max")!)
    #expect(max?.tab == .max)
    #expect(max?.route == nil)

    let home = DeepLinkParser.parse(URL(string: "posthog-ios://home")!)
    #expect(home?.tab == .home)
  }

  @Test func rejectsForeignSchemesAndJunk() {
    #expect(DeepLinkParser.parse(URL(string: "posthog://dashboard/45")!) == nil)
    #expect(DeepLinkParser.parse(URL(string: "https://example.com/dashboard/45")!) == nil)
    #expect(DeepLinkParser.parse(URL(string: "posthog-ios://dashboard/abc")!) == nil)
    #expect(DeepLinkParser.parse(URL(string: "posthog-ios://unknown/1")!) == nil)
  }
}
