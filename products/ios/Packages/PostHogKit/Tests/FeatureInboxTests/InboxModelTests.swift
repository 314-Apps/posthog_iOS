import Foundation
import PostHogAPI
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureInbox

private func makeEvent(id: String, createdAt: Date = .distantPast) -> NotificationEvent {
  NotificationEvent(id: id, type: .alertFiring, title: id, createdAt: createdAt)
}

@Suite struct InboxGroupingTests {
  @Test func bucketsEventsByAgeAgainstInjectedNow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let events = [
      makeEvent(id: "old", createdAt: now.addingTimeInterval(-10 * 86_400)),
      makeEvent(id: "recent", createdAt: now.addingTimeInterval(-3 * 86_400)),
      makeEvent(id: "fresh", createdAt: now),
    ]

    let groups = InboxGrouping.grouped(events, now: now, calendar: .current)

    #expect(groups.map(\.section) == [.today, .thisWeek, .earlier])
    #expect(groups.map { $0.events.map(\.id) } == [["fresh"], ["recent"], ["old"]])
  }

  @Test func dropsEmptySections() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let groups = InboxGrouping.grouped([makeEvent(id: "fresh", createdAt: now)], now: now)

    #expect(groups.map(\.section) == [.today])
  }
}

@Suite struct InboxFilterTests {
  private static let allTypes: [NotificationEvent.EventType] = [
    .commentMention, .alertFiring, .approvalRequested, .approvalResolved,
    .pipelineFailure, .issueAssigned, .unknown,
  ]

  @Test(arguments: [
    (InboxFilter.all, allTypes),
    (InboxFilter.alerts, [.alertFiring]),
    (InboxFilter.mentions, [.commentMention]),
    (InboxFilter.errors, [.pipelineFailure, .issueAssigned]),
  ])
  func selectsOnlyItsTypes(filter: InboxFilter, expected: [NotificationEvent.EventType]) {
    #expect(Self.allTypes.filter { filter.matches($0) } == expected)
  }
}

@MainActor
@Suite struct InboxModelTests {
  private let pageJSON = #"""
    {"count": 1, "next": null, "previous": null, "results": [
      {"id": "n1", "type": "alert_firing", "title": "Alert",
       "created_at": "2026-03-14T09:26:53Z", "is_read": false}
    ]}
    """#

  private func makeModel(transport: StubTransport) -> InboxModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("inbox-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(
      region: .us,
      projectID: 1,
      client: client,
      cache: DiskCache(root: cacheRoot)
    )
    return InboxModel(context: context)
  }

  @Test func markReadUpdatesOptimisticallyOnSuccess() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(pageJSON.utf8)),
      .response(status: 200, body: Data()),
    ])
    let model = makeModel(transport: transport)

    await model.load()
    #expect(model.events.first?.isRead == false)

    await model.setRead(true, id: "n1")

    #expect(model.events.first?.isRead == true)
    #expect(
      transport.requests[1].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/notifications/n1/mark_read/")
    #expect(transport.requests[1].httpMethod == "POST")
  }

  @Test func markReadRevertsWhenTheAPIFails() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(pageJSON.utf8)),
      .response(status: 500, body: Data()),
    ])
    let model = makeModel(transport: transport)

    await model.load()
    await model.setRead(true, id: "n1")

    #expect(model.events.first?.isRead == false)
  }

  @Test func markUnreadHitsTheUnreadEndpoint() async {
    let readPageJSON = pageJSON.replacingOccurrences(of: #""is_read": false"#, with: #""is_read": true"#)
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(readPageJSON.utf8)),
      .response(status: 200, body: Data()),
    ])
    let model = makeModel(transport: transport)

    await model.load()
    await model.setRead(false, id: "n1")

    #expect(model.events.first?.isRead == false)
    #expect(
      transport.requests[1].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/notifications/n1/mark_unread/")
  }
}
