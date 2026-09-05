import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

private let listJSON = """
  {
    "count": 3,
    "next": null,
    "previous": null,
    "results": [
      {
        "id": "c1",
        "title": "Signup funnel drop",
        "status": "idle",
        "created_at": "2026-08-30T10:15:00Z"
      },
      {"id": "c2", "title": null, "status": null},
      {"id": "c3", "created_at": "not a date"}
    ]
  }
  """

@Suite struct ConversationAPITests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  @Test func decodesConversationsDefensively() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(listJSON.utf8))
    ])
    let client = makeClient(transport: transport)
    let page = try await client.conversations(projectID: 1)

    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/conversations/")
    #expect(page.results.map(\.id) == ["c1", "c2", "c3"])

    let full = page.results[0]
    #expect(full.title == "Signup funnel drop")
    #expect(full.status == "idle")
    #expect(full.createdAt == Date(timeIntervalSince1970: 1_788_084_900))

    let minimal = page.results[1]
    #expect(minimal.title == nil)
    #expect(minimal.status == nil)
    #expect(minimal.createdAt == nil)

    #expect(page.results[2].createdAt == nil)
  }

  @Test func deletesConversation() async throws {
    let transport = StubTransport(script: [
      .response(status: 204, body: Data())
    ])
    let client = makeClient(transport: transport)
    try await client.deleteConversation(projectID: 1, conversationID: "c1")

    #expect(transport.requests[0].httpMethod == "DELETE")
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/conversations/c1/")
  }
}
