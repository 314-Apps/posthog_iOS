import Foundation
import PostHogFoundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI
@testable import PostHogQueries

@Suite struct QueryRunnerTests {
  private func makeRunner(transport: StubTransport) -> QueryRunner {
    QueryRunner(
      client: APIClient(
        baseURL: URL(string: "https://us.posthog.com")!,
        transport: transport,
        tokens: StubTokens(),
        clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
      )
    )
  }

  private let trendsQuery = DataQuery.trends(
    TrendsQuery.make(
      series: [TrendsQuery.eventsNode(math: "dau")],
      interval: "day",
      dateFrom: "-7d"
    )
  )

  private let directResult = Data(
    #"{"results":[{"label":"dau","count":9,"data":[4,5],"labels":["a","b"],"days":["2026-03-13","2026-03-14"]}]}"#
      .utf8
  )

  @Test func synchronousResponseParsesDirectly() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: directResult)])
    let runner = makeRunner(transport: transport)
    let result = try await runner.run(trendsQuery, projectID: 1)
    guard case .series(let series) = result else {
      Issue.record("expected series")
      return
    }
    #expect(series.count == 1)
    #expect(series[0].data == [4, 5])

    let request = transport.requests[0]
    #expect(request.url?.absoluteString == "https://us.posthog.com/api/projects/1/query/")
    let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
    #expect(body["query"]?["kind"]?.stringValue == "TrendsQuery")
    #expect(body["refresh"]?.stringValue == "blocking")
    #expect(body["client_query_id"]?.stringValue?.hasPrefix("ios-") == true)
  }

  @Test func asyncEnvelopePollsUntilComplete() async throws {
    let incomplete = #"{"query_status":{"id":"q1","complete":false}}"#
    let complete = #"""
      {"query_status":{"id":"q1","complete":true,"results":{"results":
      [{"label":"dau","count":2,"data":[2],"labels":["a"],"days":["2026-03-14"]}]}}}
      """#.replacingOccurrences(of: "\n", with: "")
    let transport = StubTransport(script: [
      .response(status: 202, body: Data(incomplete.utf8)),
      .response(status: 200, body: Data(incomplete.utf8)),
      .response(status: 200, body: Data(complete.utf8)),
    ])
    let runner = makeRunner(transport: transport)
    let result = try await runner.run(trendsQuery, projectID: 1, refresh: .lazyAsync)
    guard case .series(let series) = result else {
      Issue.record("expected series")
      return
    }
    #expect(series[0].data == [2])
    #expect(transport.callCount == 3)
    #expect(transport.requests[1].url?.absoluteString == "https://us.posthog.com/api/projects/1/query/q1/")
    #expect(transport.requests[1].httpMethod == "GET")
  }

  @Test func pollErrorSurfacesMessage() async {
    let incomplete = #"{"query_status":{"id":"q2","complete":false}}"#
    let failed = #"{"query_status":{"id":"q2","complete":false,"error_message":"Estimated query size too large"}}"#
    let transport = StubTransport(script: [
      .response(status: 202, body: Data(incomplete.utf8)),
      .response(status: 200, body: Data(failed.utf8)),
    ])
    let runner = makeRunner(transport: transport)
    do {
      _ = try await runner.run(trendsQuery, projectID: 1, refresh: .async)
      Issue.record("expected failure")
    } catch let error as QueryRunnerError {
      guard case .queryFailed(let message) = error else {
        Issue.record("expected queryFailed, got \(error)")
        return
      }
      #expect(message == "Estimated query size too large")
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func insightVizUnwrapsForParsing() async throws {
    let wrapped = DataQuery(raw: [
      "kind": "InsightVizNode",
      "source": trendsQuery.raw,
    ])
    let transport = StubTransport(script: [.response(status: 200, body: directResult)])
    let runner = makeRunner(transport: transport)
    let result = try await runner.run(wrapped, projectID: 1)
    guard case .series = result else {
      Issue.record("expected series from unwrapped source kind")
      return
    }
  }
}
