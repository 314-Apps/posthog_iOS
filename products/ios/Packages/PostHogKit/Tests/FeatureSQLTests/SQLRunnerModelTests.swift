import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureSQL

private let tableResponse = Data(
  #"{"columns":["event","total"],"results":[["$pageview",120],["$autocapture",42]],"hasMore":false}"#.utf8
)

private func makeContext(transport: StubTransport, projectID: Int = 1) -> ProjectContext {
  let client = APIClient(
    baseURL: URL(string: "https://us.posthog.com")!,
    transport: transport,
    tokens: StubTokens(),
    clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
  )
  let cacheRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("sql-tests-\(UUID().uuidString)", isDirectory: true)
  return ProjectContext(
    region: .us,
    projectID: projectID,
    client: client,
    cache: DiskCache(root: cacheRoot)
  )
}

private func makeDefaults() -> UserDefaults {
  UserDefaults(suiteName: "sql-tests-\(UUID().uuidString)")!
}

@MainActor
@Suite struct SQLRunnerModelTests {
  @Test func runSuccessPopulatesResultAndHistory() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: tableResponse)])
    let model = SQLRunnerModel(context: makeContext(transport: transport), defaults: makeDefaults())
    await model.run()
    let result = try #require(model.result)
    #expect(result.columns == ["event", "total"])
    #expect(result.rows.count == 2)
    #expect(model.errorText == nil)
    #expect(!model.isRunning)
    #expect(model.history == [model.queryText])

    let request = try #require(transport.requests.first)
    #expect(request.url?.path() == "/api/projects/1/query/")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["query"]?["kind"]?.stringValue == "HogQLQuery")
    #expect(body["query"]?["query"]?.stringValue == model.queryText)
    #expect(body["refresh"]?.stringValue == "blocking")
  }

  @Test func serverErrorSurfacesVerbatimMessage() async {
    let failed = Data(
      #"{"query_status":{"complete":false,"error_message":"Unable to resolve field: bogus"}}"#.utf8
    )
    let transport = StubTransport(script: [.response(status: 200, body: failed)])
    let model = SQLRunnerModel(context: makeContext(transport: transport), defaults: makeDefaults())
    await model.run()
    #expect(model.errorText == "Unable to resolve field: bogus")
    #expect(model.result == nil)
    #expect(model.history.isEmpty)
    #expect(!model.isRunning)
  }

  @Test func transportFailureShowsGenericMessage() async {
    let transport = StubTransport(script: [.error(URLError(.notConnectedToInternet))])
    let model = SQLRunnerModel(context: makeContext(transport: transport), defaults: makeDefaults())
    await model.run()
    #expect(model.errorText == "Couldn't run the query. Check your connection and try again.")
    #expect(model.history.isEmpty)
  }

  @Test func doubleRunBlockedWhileInFlight() async {
    let transport = StubTransport(script: [
      .slowResponse(status: 200, body: tableResponse, delay: 0.1)
    ])
    let model = SQLRunnerModel(context: makeContext(transport: transport), defaults: makeDefaults())
    async let first: Void = model.run()
    var spins = 0
    while transport.callCount == 0, spins < 100_000 {
      spins += 1
      await Task.yield()
    }
    #expect(model.isRunning)
    await model.run()
    await first
    #expect(transport.callCount == 1)
    #expect(model.history.count == 1)
  }

  @Test func historyDedupesCapsAndPersistsAcrossInstances() async {
    let queries = (0...10).map { "SELECT \($0)" }
    let script = Array(
      repeating: StubTransport.Scripted.response(status: 200, body: tableResponse),
      count: queries.count + 1
    )
    let defaults = makeDefaults()
    let model = SQLRunnerModel(
      context: makeContext(transport: StubTransport(script: script)),
      defaults: defaults
    )
    for query in queries {
      model.queryText = query
      await model.run()
    }
    #expect(model.history.count == 10)
    #expect(model.history.first == "SELECT 10")
    #expect(!model.history.contains("SELECT 0"))

    model.queryText = "SELECT 1"
    await model.run()
    #expect(model.history.count == 10)
    #expect(model.history.first == "SELECT 1")
    #expect(model.history.filter { $0 == "SELECT 1" }.count == 1)

    let reloaded = SQLRunnerModel(
      context: makeContext(transport: StubTransport(script: [])),
      defaults: defaults
    )
    #expect(reloaded.history == model.history)

    reloaded.removeFromHistory("SELECT 1")
    let afterDelete = SQLRunnerModel(
      context: makeContext(transport: StubTransport(script: [])),
      defaults: defaults
    )
    #expect(!afterDelete.history.contains("SELECT 1"))
    #expect(afterDelete.history.count == 9)

    let otherProject = SQLRunnerModel(
      context: makeContext(transport: StubTransport(script: []), projectID: 2),
      defaults: defaults
    )
    #expect(otherProject.history.isEmpty)
  }

  @Test func emptyTextNeverSendsARequest() async {
    let transport = StubTransport(script: [])
    let model = SQLRunnerModel(context: makeContext(transport: transport), defaults: makeDefaults())
    model.queryText = "   \n  "
    await model.run()
    #expect(transport.callCount == 0)
    #expect(!model.isRunning)
    #expect(model.errorText == nil)
  }
}
