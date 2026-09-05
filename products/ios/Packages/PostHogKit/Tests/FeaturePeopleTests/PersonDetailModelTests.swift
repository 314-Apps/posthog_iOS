import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeaturePeople

@MainActor
@Suite struct PersonDetailModelTests {
  private func makeModel(transport: StubTransport) -> PersonDetailModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-people-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return PersonDetailModel(context: context, personID: "5")
  }

  private let personBody = Data(
    #"{"id": 5, "uuid": "0192-abc", "distinct_ids": ["d-1"], "properties": {"email": "ana@example.com"}}"#
      .utf8
  )

  @Test func runsTheEventsQueryAndParsesRows() async throws {
    let queryBody = #"""
      {"columns": ["event", "timestamp"], "results": [
      ["$pageview", "2026-09-03T10:00:00Z"],
      ["signup", "2026-09-02T09:30:00.500Z"]], "hasMore": false}
      """#
    let transport = StubTransport(script: [
      .response(status: 200, body: personBody),
      .response(status: 200, body: Data(queryBody.utf8)),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    #expect(model.person?.displayName == "ana@example.com")
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/persons/5/")

    let queryRequest = transport.requests[1]
    #expect(queryRequest.url?.absoluteString == "https://us.posthog.com/api/projects/1/query/")
    #expect(queryRequest.httpMethod == "POST")
    let body = try JSONDecoder().decode(JSONValue.self, from: queryRequest.httpBody ?? Data())
    #expect(body["query"]?["kind"]?.stringValue == "EventsQuery")
    #expect(body["query"]?["select"] == ["event", "timestamp"])
    #expect(body["query"]?["personId"]?.stringValue == "0192-abc")
    #expect(body["query"]?["orderBy"] == ["timestamp DESC"])
    #expect(body["query"]?["limit"]?.intValue == 20)

    guard case .loaded(let rows) = model.events else {
      Issue.record("expected loaded events, got \(model.events)")
      return
    }
    #expect(rows.map(\.event) == ["$pageview", "signup"])
    #expect(rows[0].timestamp != nil)
    #expect(rows[1].timestamp != nil)
  }

  @Test func eventsQueryFailureMarksEventsFailed() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: personBody),
      .response(status: 500, body: Data()),
    ])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.person != nil)
    #expect(model.events == .failed)
  }

  @Test func failedPersonLoadFlagsTheFailure() async {
    let transport = StubTransport(script: [.response(status: 500, body: Data())])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.person == nil)
    #expect(model.loadFailed)
    // No events query runs without a person to key it on.
    #expect(transport.callCount == 1)
  }
}
