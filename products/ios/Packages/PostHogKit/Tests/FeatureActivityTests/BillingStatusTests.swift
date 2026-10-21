import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

private let billingJSON = #"""
  {
    "billing_plan": "scale",
    "customer_id": "cus_fake123",
    "has_active_subscription": true,
    "products": [
      {
        "name": "Product analytics",
        "type": "product_analytics",
        "current_usage": 812345,
        "usage_limit": 1000000,
        "percentage_usage": 81.2,
        "unmodeled_key": {"nested": [1, 2]}
      },
      {
        "name": "Session replay",
        "type": "session_replay",
        "current_usage": 4200
      },
      "junk",
      {
        "type": "feature_flags",
        "current_usage": "lots",
        "usage_limit": null,
        "percentage_usage": {"nested": true}
      }
    ]
  }
  """#

@Suite struct BillingStatusTests {
  @Test func parsesProductsDefensively() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: Data(billingJSON.utf8))])
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let status = try await client.billingStatus()

    #expect(transport.requests[0].url?.absoluteString == "https://us.posthog.com/api/billing/")
    #expect(status.planName == "scale")
    #expect(status.products.count == 3)

    let analytics = status.products[0]
    #expect(analytics.name == "Product analytics")
    #expect(analytics.type == "product_analytics")
    #expect(analytics.currentUsage == 812_345)
    #expect(analytics.usageLimit == 1_000_000)
    #expect(analytics.percentageUsage == 81.2)

    let replay = status.products[1]
    #expect(replay.currentUsage == 4200)
    #expect(replay.usageLimit == nil)
    #expect(replay.percentageUsage == nil)

    let flags = status.products[2]
    #expect(flags.name == nil)
    #expect(flags.type == "feature_flags")
    #expect(flags.currentUsage == nil)
    #expect(flags.usageLimit == nil)
    #expect(flags.percentageUsage == nil)
  }

  @Test(arguments: [
    (#"{"subscription": {"plan": {"name": "Teams"}}}"#, "Teams"),
    (#"{"products": [{"current_plan": {"name": "Free"}}]}"#, "Free"),
    ("{}", nil),
    ("[1, 2, 3]", nil),
  ])
  func planNameFallsBackWithoutThrowing(json: String, expected: String?) throws {
    let status = try APIClient.makeDecoder().decode(BillingStatus.self, from: Data(json.utf8))
    #expect(status.planName == expected)
  }
}
