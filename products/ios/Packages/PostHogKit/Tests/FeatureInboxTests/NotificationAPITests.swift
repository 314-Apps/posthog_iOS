import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

@testable import FeatureInbox

private let fixtureJSON = """
  {
    "count": 7,
    "next": null,
    "previous": null,
    "results": [
      {
        "id": "n1",
        "type": "alert_firing",
        "title": "CPU alert fired",
        "body": "Threshold crossed on the hourly trend",
        "priority": "critical",
        "created_at": "2026-03-14T09:26:53Z",
        "is_read": false,
        "resource_type": "insight",
        "resource_id": "42"
      },
      {
        "id": "n2",
        "type": "comment_mention",
        "title": "Mentioned you on a dashboard",
        "created_at": "2026-03-14T08:00:00.120Z",
        "is_read": true
      },
      {
        "id": "n3",
        "type": "approval_requested",
        "title": "Approval needed",
        "priority": "normal",
        "created_at": "2026-03-13T09:00:00Z"
      },
      {
        "id": "n4",
        "type": "approval_resolved",
        "title": "Change approved",
        "created_at": "2026-03-12T09:00:00Z"
      },
      {
        "id": "n5",
        "type": "pipeline_failure",
        "title": "Export destination failed",
        "priority": "shouting",
        "created_at": "2026-03-11T09:00:00Z"
      },
      {
        "id": "n6",
        "type": "issue_assigned",
        "title": "Issue assigned to you",
        "created_at": "2026-03-10T09:00:00Z",
        "resource_type": "error_issue",
        "resource_id": "abc-123"
      },
      {
        "id": "n7",
        "type": "carrier_pigeon",
        "title": "Mystery"
      }
    ]
  }
  """

@Suite struct NotificationAPITests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  @Test func decodesAllTypesDefensively() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(fixtureJSON.utf8))
    ])
    let client = makeClient(transport: transport)
    let page = try await client.notifications(projectID: 1)

    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/notifications/")
    #expect(page.results.count == 7)
    #expect(
      page.results.map(\.type) == [
        .alertFiring, .commentMention, .approvalRequested, .approvalResolved,
        .pipelineFailure, .issueAssigned, .unknown,
      ])

    let alert = page.results[0]
    #expect(alert.priority == .critical)
    #expect(alert.resourceType == "insight")
    #expect(alert.resourceID == "42")

    let mention = page.results[1]
    #expect(mention.body == nil)
    #expect(mention.isRead)

    let failure = page.results[4]
    #expect(failure.priority == .unknown)

    let mystery = page.results[6]
    #expect(mystery.type == .unknown)
    #expect(mystery.title == "Mystery")
    #expect(mystery.body == nil)
    #expect(mystery.priority == .normal)
    #expect(mystery.createdAt == .distantPast)
    #expect(!mystery.isRead)
    #expect(mystery.resourceType == nil)
    #expect(mystery.resourceID == nil)
  }

  @Test func decodesUnreadCount() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(#"{"count": 12}"#.utf8))
    ])
    let client = makeClient(transport: transport)
    let count = try await client.notificationUnreadCount(projectID: 1)

    #expect(count == 12)
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/notifications/unread_count/")
  }
}
