import Foundation
import PostHogAPI
import PostHogQueries
import Testing

@testable import FeatureMax

@Suite struct MaxStreamEventTests {
  static let classificationCases: [(ServerSentEvent, MaxStreamEvent)] = [
    (
      ServerSentEvent(event: "message", data: #"{"type":"ai","id":"m1","content":"Hello"}"#),
      .message(role: .assistant, id: "m1", content: "Hello")
    ),
    (
      ServerSentEvent(event: "message", data: #"{"type":"human","id":"h1","content":"Hi Max"}"#),
      .message(role: .user, id: "h1", content: "Hi Max")
    ),
    (
      ServerSentEvent(event: "message", data: #"{"type":"ai","content":"no id"}"#),
      .message(role: .assistant, id: nil, content: "no id")
    ),
    (
      ServerSentEvent(event: "message", data: #"{"type":"ai/reasoning","content":"thinking..."}"#),
      .ignored
    ),
    (
      ServerSentEvent(event: "message", data: #"{"type":"ai/failure","content":"boom"}"#),
      .ignored
    ),
    (
      ServerSentEvent(event: "message", data: "not json at all"),
      .ignored
    ),
    (
      ServerSentEvent(event: "message", data: #"{"type":"ai/viz"}"#),
      .ignored
    ),
    (
      ServerSentEvent(event: "status", data: #"{"type":"ack"}"#),
      .ignored
    ),
    (
      ServerSentEvent(event: nil, data: #"{"type":"ai","content":"eventless"}"#),
      .ignored
    ),
    (
      ServerSentEvent(event: "conversation", data: #"{"id":"c1","status":"idle","title":"Signups"}"#),
      .conversationUpdate(status: "idle", title: "Signups")
    ),
    (
      ServerSentEvent(event: "conversation", data: #"{"id":"c1"}"#),
      .conversationUpdate(status: nil, title: nil)
    ),
  ]

  @Test(arguments: classificationCases.indices)
  func classifiesFrames(index: Int) {
    let (frame, expected) = Self.classificationCases[index]
    #expect(MaxStreamEvent.parse(frame) == expected)
  }

  @Test func vizFrameCarriesQueryAndAnswerBody() throws {
    let data = """
      {"type": "ai/viz", "id": "v1", "answer": {
        "query": {"kind": "TrendsQuery", "series": [{"kind": "EventsNode"}]},
        "results": [{"label": "signups", "data": [1, 2, 3]}]
      }}
      """
    let event = MaxStreamEvent.parse(ServerSentEvent(event: "message", data: data))
    guard case .visualization(let query, let answerBody) = event else {
      Issue.record("expected a visualization, got \(event)")
      return
    }
    #expect(query?.kind == "TrendsQuery")
    #expect(answerBody["results"]?.arrayValue?.count == 1)
  }

  @Test func vizFrameWithoutQueryKeepsRawAnswer() {
    let data = #"{"type":"ai/viz","answer":{"results":[{"label":"x"}]}}"#
    let event = MaxStreamEvent.parse(ServerSentEvent(event: "message", data: data))
    guard case .visualization(let query, let answerBody) = event else {
      Issue.record("expected a visualization, got \(event)")
      return
    }
    #expect(query == nil)
    #expect(answerBody["results"] != nil)
  }
}
