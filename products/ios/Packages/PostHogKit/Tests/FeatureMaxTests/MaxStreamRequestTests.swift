import Foundation
import Testing

@testable import FeatureMax

@Suite struct MaxStreamRequestTests {
  @Test func buildsURLBodyAndHeaders() throws {
    let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let traceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let request = MaxStreamRequest(
      baseURL: URL(string: "https://us.posthog.com")!,
      projectID: 42,
      accessToken: "pha_token",
      conversationID: conversationID,
      message: "What changed in signups?",
      traceID: traceID
    )

    #expect(request.url.absoluteString == "https://us.posthog.com/api/projects/42/conversations/")
    #expect(
      request.headers == [
        "Authorization": "Bearer pha_token",
        "Content-Type": "application/json",
        // Dropping application/json here makes the server refuse the stream
        // with a 406 before the view runs.
        "Accept": "text/event-stream, application/json",
      ])

    let json = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
    #expect(
      json == [
        "conversation": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "content": "What changed in signups?",
        "trace_id": "11111111-2222-3333-4444-555555555555",
      ])
  }

  @Test func mintsAFreshTraceIDPerRequest() throws {
    let conversationID = UUID()
    func traceID() throws -> String {
      let request = MaxStreamRequest(
        baseURL: URL(string: "https://us.posthog.com")!,
        projectID: 1,
        accessToken: "pha_token",
        conversationID: conversationID,
        message: "hi"
      )
      let json = try JSONSerialization.jsonObject(with: request.body) as? [String: String]
      return try #require(json?["trace_id"])
    }
    let first = try traceID()
    let second = try traceID()
    #expect(UUID(uuidString: first) != nil)
    #expect(first != second)
  }
}
