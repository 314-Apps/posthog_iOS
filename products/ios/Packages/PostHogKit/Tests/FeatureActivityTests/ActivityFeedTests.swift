import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

@testable import FeatureActivity

private let feedJSON = #"""
  {
    "count": 3,
    "next": null,
    "previous": null,
    "results": [
      {
        "id": "0195f9a2-1111-7000-8000-000000000001",
        "activity": "updated",
        "scope": "FeatureFlag",
        "item_id": "42",
        "is_system": false,
        "unread": true,
        "created_at": "2026-03-14T09:26:53Z",
        "user": {"first_name": "Kim", "email": "kim@example.com"},
        "detail": {"changes": []}
      },
      {
        "id": "0195f9a2-1111-7000-8000-000000000002",
        "activity": "exported",
        "scope": "Insight",
        "created_at": "2026-03-14T08:00:00.120Z",
        "user": null
      },
      {
        "id": "0195f9a2-1111-7000-8000-000000000003",
        "activity": "deleted"
      }
    ]
  }
  """#

@Suite struct ActivityFeedTests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  @Test func sendsScopeQueryAndDecodesDefensively() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: Data(feedJSON.utf8))])
    let client = makeClient(transport: transport)
    let page = try await client.activityLog(projectID: 1, scope: "FeatureFlag")

    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/activity_log/?scope=FeatureFlag")
    #expect(page.results.count == 3)

    let flagEntry = page.results[0]
    #expect(flagEntry.scope == "FeatureFlag")
    #expect(flagEntry.activity == "updated")
    #expect(flagEntry.actorName == "Kim")

    let bare = page.results[2]
    #expect(bare.scope == nil)
    #expect(bare.createdAt == .distantPast)
    #expect(bare.actorName == "Someone")
  }

  @Test func omitsScopeQueryForAll() async throws {
    let empty = #"{"count": 0, "next": null, "previous": null, "results": []}"#
    let transport = StubTransport(script: [.response(status: 200, body: Data(empty.utf8))])
    let client = makeClient(transport: transport)
    _ = try await client.activityLog(projectID: 1)

    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/activity_log/")
  }

  @Test(arguments: [
    ("updated", "FeatureFlag", "Someone updated a feature flag"),
    ("created", "Experiment", "Someone created an experiment"),
    ("deleted", nil, "Someone deleted an item"),
    ("exported_for_opengraph_image", "Insight", "Someone exported for opengraph image an insight"),
    ("updated", "SessionRecordingPlaylist", "Someone updated a session recording playlist"),
  ])
  func buildsFeedLines(activity: String, scope: String?, expected: String) {
    let entry = ProjectActivityEntry(
      id: "1",
      activity: activity,
      scope: scope,
      createdAt: .distantPast,
      user: nil
    )
    #expect(ActivityPhrasing.line(for: entry) == expected)
  }
}
