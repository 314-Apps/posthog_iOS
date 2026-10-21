import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureWeb

@MainActor
@Suite struct WebAnalyticsModelTests {
  private func makeModel(transport: StubTransport) -> WebAnalyticsModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-web-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return WebAnalyticsModel(context: context)
  }

  /// The sections run concurrently, so the stub cannot know which query
  /// consumes which scripted response. One body serves them all: the overview
  /// parser keeps only the object row, the breakdown parser only the array row.
  private let sharedBody = Data(
    #"{"results":[{"key":"visitors","value":812,"kind":"unit"},["Desktop",64,180]]}"#.utf8
  )

  private func recordedQueries(_ transport: StubTransport) throws -> [JSONValue] {
    try transport.requests.compactMap { request in
      try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())["query"]
    }
  }

  @Test func loadRunsEverySectionAndParsesEachShape() async throws {
    let transport = StubTransport(
      script: Array(repeating: .response(status: 200, body: sharedBody), count: 4)
    )
    let model = makeModel(transport: transport)
    await model.load()

    guard case .loaded(let items) = model.overview else {
      Issue.record("expected loaded overview")
      return
    }
    #expect(items.map(\.key) == ["visitors"])
    #expect(items.first?.value == 812)
    for state in [model.pages, model.referrers, model.devices] {
      guard case .loaded(let rows) = state else {
        Issue.record("expected loaded breakdown")
        continue
      }
      #expect(rows == [WebStatsRow(label: "Desktop", visitors: 64, views: 180)])
    }

    #expect(transport.callCount == 4)
    let queries = try recordedQueries(transport)
    #expect(queries.count(where: { $0["kind"]?.stringValue == "WebOverviewQuery" }) == 1)
    let tables = queries.filter { $0["kind"]?.stringValue == "WebStatsTableQuery" }
    #expect(
      Set(tables.compactMap { $0["breakdownBy"]?.stringValue })
        == ["Page", "InitialReferringDomain", "DeviceType"]
    )
    for query in queries {
      #expect(query["dateRange"]?["date_from"]?.stringValue == "-7d")
    }
    for table in tables {
      #expect(table["limit"]?.intValue == 10)
      #expect(table["properties"] == .array([]))
    }
  }

  @Test func dateChangeReRunsEverySectionWithTheNewRange() async throws {
    let transport = StubTransport(
      script: Array(repeating: .response(status: 200, body: sharedBody), count: 4)
    )
    let model = makeModel(transport: transport)
    model.datePreset = .day
    await model.reload()

    let queries = try recordedQueries(transport)
    #expect(queries.count == 4)
    for query in queries {
      #expect(query["dateRange"]?["date_from"]?.stringValue == "-24h")
    }
  }
}
