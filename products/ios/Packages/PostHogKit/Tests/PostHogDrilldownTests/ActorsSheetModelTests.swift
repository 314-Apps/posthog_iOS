import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import PostHogDrilldown

private let sourceQuery = DataQuery(raw: [
  "kind": "TrendsQuery",
  "interval": "day",
  "dateRange": ["date_from": "-7d"],
  "series": [["kind": "EventsNode", "event": "checkout_completed"]],
])

private let drill = ActorsDrill.trendsPoint(
  day: "2026-02-03",
  series: 0,
  breakdown: nil,
  compare: nil
)

private struct SamplePerson {
  let id: String
  let email: String
  let distinctID: String
}

private let firstPagePeople = [
  SamplePerson(
    id: "aaaa1111-0000-4000-8000-00000000da01",
    email: "rosa@example.com",
    distinctID: "rosa-01"
  ),
  SamplePerson(
    id: "aaaa1111-0000-4000-8000-00000000da02",
    email: "kim@example.com",
    distinctID: "kim-02"
  ),
]

private let secondPagePeople = [
  SamplePerson(
    id: "aaaa1111-0000-4000-8000-00000000da03",
    email: "arun@example.com",
    distinctID: "arun-03"
  )
]

private let sampleHogQL = "SELECT id FROM persons WHERE id IN (SELECT person_id FROM events)"

private func actorsPage(_ people: [SamplePerson], hasMore: Bool, missing: Int = 0) -> Data {
  let rows = people.map { person in
    """
    [{"id":"\(person.id)","distinct_ids":["\(person.distinctID)"],\
    "properties":{"email":"\(person.email)"}}]
    """
  }
  return Data(
    """
    {"columns":["person"],"results":[\(rows.joined(separator: ","))],\
    "hasMore":\(hasMore),"hogql":"\(sampleHogQL)","missing_actors_count":\(missing)}
    """.utf8
  )
}

private func makeContext(transport: StubTransport) -> ProjectContext {
  let client = APIClient(
    baseURL: URL(string: "https://us.posthog.com")!,
    transport: transport,
    tokens: StubTokens(),
    clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
  )
  let cacheRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("drilldown-tests-\(UUID().uuidString)", isDirectory: true)
  return ProjectContext(
    region: .us,
    projectID: 7,
    client: client,
    cache: DiskCache(root: cacheRoot)
  )
}

@MainActor
private func makeModel(_ transport: StubTransport) -> ActorsSheetModel {
  ActorsSheetModel(context: makeContext(transport: transport), source: sourceQuery, drill: drill)
}

private func sentQuery(_ transport: StubTransport, at index: Int) throws -> JSONValue {
  let request = try #require(transport.requests[safe: index])
  let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
  return try #require(body["query"])
}

/// Reads a field by name wherever the builder put it. The builder is another
/// module's code, so pin the value the request carries, not its nesting.
private func firstValue(_ key: String, in value: JSONValue) -> JSONValue? {
  var queue = [value]
  while !queue.isEmpty {
    let next = queue.removeFirst()
    if let found = next[key] { return found }
    if let object = next.objectValue { queue.append(contentsOf: object.values) }
    if let array = next.arrayValue { queue.append(contentsOf: array) }
  }
  return nil
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

@MainActor
@Suite struct ActorsSheetModelTests {
  @Test func firstPageParsesRowsAndSendsAnActorsQuery() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: true, missing: 2))
    ])
    let model = makeModel(transport)
    await model.loadFirstPage()

    #expect(model.rows.map(\.displayName) == ["rosa@example.com", "kim@example.com"])
    #expect(model.rows.first?.distinctID == "rosa-01")
    #expect(model.rows.first?.id == "aaaa1111-0000-4000-8000-00000000da01")
    #expect(model.hasMore)
    #expect(model.hogql == sampleHogQL)
    #expect(model.missingActorsCount == 2)
    #expect(model.errorText == nil)
    #expect(!model.isLoading)

    let request = try #require(transport.requests.first)
    #expect(request.url?.path() == "/api/projects/7/query/")
    let query = try sentQuery(transport, at: 0)
    #expect(query["kind"]?.stringValue == "ActorsQuery")
    #expect(firstValue("limit", in: query)?.intValue == ActorsSheetModel.pageSize)
    #expect(firstValue("offset", in: query)?.intValue == 0)
  }

  @Test func loadMoreAppendsTheNextPageAndAdvancesTheOffset() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: true)),
      .response(status: 200, body: actorsPage(secondPagePeople, hasMore: false)),
    ])
    let model = makeModel(transport)
    await model.loadFirstPage()
    await model.loadMore()

    let secondQuery = try sentQuery(transport, at: 1)
    #expect(model.rows.map(\.distinctID) == ["rosa-01", "kim-02", "arun-03"])
    #expect(!model.hasMore)
    #expect(model.errorText == nil)
    #expect(firstValue("offset", in: secondQuery)?.intValue == 2)

    // hasMore is false now, so the sentinel cannot fetch a third page.
    await model.loadMore()
    #expect(transport.callCount == 2)
  }

  @Test func searchRerunsTheQueryWithTheTerm() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: false)),
      .response(status: 200, body: actorsPage([firstPagePeople[0]], hasMore: false)),
    ])
    let model = makeModel(transport)
    await model.loadFirstPage()
    model.search = "rosa"
    await model.loadFirstPage()

    let firstQuery = try sentQuery(transport, at: 0)
    let secondQuery = try sentQuery(transport, at: 1)
    #expect(transport.callCount == 2)
    #expect(model.rows.map(\.distinctID) == ["rosa-01"])
    #expect(firstValue("search", in: secondQuery)?.stringValue == "rosa")
    #expect(firstValue("search", in: firstQuery) == nil)
  }

  @Test func aFailedReloadKeepsTheRowsAlreadyOnScreen() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: false)),
      .error(URLError(.timedOut)),
    ])
    let model = makeModel(transport)
    await model.loadFirstPage()
    model.search = "kim"
    await model.loadFirstPage()

    #expect(model.errorText == "Couldn't load these people. Try again.")
    #expect(model.rows.map(\.distinctID) == ["rosa-01", "kim-02"])
    #expect(!model.isLoading)
  }

  @Test func repeatingTheFirstPageLoadDoesNotDoubleAppend() async {
    // The appear task and the debounced search task both call loadFirstPage.
    let transport = StubTransport(script: [
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: false)),
      .response(status: 200, body: actorsPage(firstPagePeople, hasMore: false)),
    ])
    let model = makeModel(transport)
    await model.loadFirstPage()
    await model.loadFirstPage()

    #expect(transport.callCount == 1)
    #expect(model.rows.count == 2)
  }
}
