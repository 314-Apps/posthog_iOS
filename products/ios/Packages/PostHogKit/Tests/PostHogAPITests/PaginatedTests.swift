import Foundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI

private struct Row: Codable, Sendable, Equatable {
  let id: Int
}

@Suite struct PaginatedTests {
  @Test func followsNextLinks() async throws {
    let page1 = #"""
      {"count":3,"next":"https://us.posthog.com/api/projects/1/rows/?offset=2",
      "previous":null,"results":[{"id":1},{"id":2}]}
      """#.replacingOccurrences(of: "\n", with: "")
    let page2 = #"{"count":3,"next":null,"previous":null,"results":[{"id":3}]}"#
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(page1.utf8)),
      .response(status: 200, body: Data(page2.utf8)),
    ])
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )

    var rows: [Row] = []
    for try await page in client.pages(startingAt: .get("/api/projects/1/rows/"), of: Row.self) {
      rows.append(contentsOf: page.results)
    }
    #expect(rows == [Row(id: 1), Row(id: 2), Row(id: 3)])
    #expect(transport.requests.count == 2)
    #expect(transport.requests[1].url?.query()?.contains("offset=2") == true)
  }
}
