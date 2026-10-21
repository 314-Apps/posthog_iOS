import Foundation
import PostHogAPI
import Testing

@testable import FeatureLive

@MainActor
@Suite struct LiveFeedModelTests {
  private func makeStartedModel() -> (LiveFeedModel, AsyncThrowingStream<ServerSentEvent, Error>.Continuation) {
    let (stream, continuation) = AsyncThrowingStream<ServerSentEvent, Error>.makeStream()
    let model = LiveFeedModel(
      events: { stream },
      now: { Date(timeIntervalSince1970: 1_788_516_000) }
    )
    model.start()
    return (model, continuation)
  }

  private func payload(event: String, distinctID: String) -> ServerSentEvent {
    ServerSentEvent(data: #"{"event":"\#(event)","distinct_id":"\#(distinctID)"}"#)
  }

  /// Yields to the stream task until the condition holds; bounded so a broken
  /// model fails the test instead of hanging CI.
  private func drain(until condition: () -> Bool) async {
    var attempts = 0
    while !condition(), attempts < 10_000 {
      attempts += 1
      await Task.yield()
    }
    #expect(condition())
  }

  @Test func decodesEventWithObjectProperties() async {
    let (model, continuation) = makeStartedModel()
    let data =
      #"{"event":"$pageview","distinct_id":"user-1","timestamp":"2026-09-04T10:00:00Z","#
      + #""properties":{"$browser":"Safari","count":2}}"#
    continuation.yield(ServerSentEvent(data: data))
    await drain { model.rows.count == 1 }
    let row = model.rows[0]
    #expect(row.event == "$pageview")
    #expect(row.distinctID == "user-1")
    #expect(row.timestamp == Date(timeIntervalSince1970: 1_788_516_000))
    #expect(row.properties["$browser"]?.stringValue == "Safari")
    #expect(row.properties["count"]?.intValue == 2)
    #expect(model.connectionState == .live)
  }

  @Test func decodesStringEncodedProperties() async {
    let (model, continuation) = makeStartedModel()
    continuation.yield(
      ServerSentEvent(
        data: #"{"event":"identify","distinct_id":"user-2","properties":"{\"plan\":\"free\"}"}"#
      )
    )
    await drain { model.rows.count == 1 }
    #expect(model.rows[0].properties["plan"]?.stringValue == "free")
  }

  @Test func dropsJunkDataLinesSilently() async {
    let (model, continuation) = makeStartedModel()
    continuation.yield(ServerSentEvent(data: "not json at all"))
    continuation.yield(ServerSentEvent(data: "[1,2,3]"))
    continuation.yield(ServerSentEvent(data: #"{"distinct_id":"no-event-key"}"#))
    continuation.yield(ServerSentEvent(data: #"{"event":42,"distinct_id":"typed-wrong"}"#))
    continuation.yield(payload(event: "survives", distinctID: "user-3"))
    await drain { model.rows.count == 1 }
    #expect(model.rows[0].event == "survives")
  }

  @Test func missingOrMalformedTimestampDecodesAsNil() async {
    let (model, continuation) = makeStartedModel()
    continuation.yield(payload(event: "no-timestamp", distinctID: "user-4"))
    continuation.yield(
      ServerSentEvent(data: #"{"event":"bad-timestamp","distinct_id":"user-5","timestamp":"yesterday"}"#)
    )
    await drain { model.rows.count == 2 }
    #expect(model.rows.allSatisfy { $0.timestamp == nil })
  }

  @Test func capsRowsAtFiveHundredNewestFirst() async {
    let (model, continuation) = makeStartedModel()
    for index in 0..<505 {
      continuation.yield(payload(event: "event-\(index)", distinctID: "user"))
    }
    continuation.finish()
    await drain { model.connectionState == .dropped }
    #expect(model.rows.count == 500)
    #expect(model.rows.first?.event == "event-504")
    #expect(model.rows.last?.event == "event-5")
  }

  @Test func pauseBuffersAndResumePrepends() async {
    let (model, continuation) = makeStartedModel()
    continuation.yield(payload(event: "event-0", distinctID: "user"))
    continuation.yield(payload(event: "event-1", distinctID: "user"))
    await drain { model.rows.count == 2 }

    model.pause()
    #expect(model.isPaused)
    continuation.yield(payload(event: "event-2", distinctID: "user"))
    continuation.yield(payload(event: "event-3", distinctID: "user"))
    continuation.yield(payload(event: "event-4", distinctID: "user"))
    await drain { model.bufferedCount == 3 }
    #expect(model.rows.count == 2)

    model.resume()
    #expect(!model.isPaused)
    #expect(model.bufferedCount == 0)
    #expect(model.rows.map(\.event) == ["event-4", "event-3", "event-2", "event-1", "event-0"])
  }

  @Test func filterMatchesEventAndDistinctIDCaseInsensitively() async {
    let (model, continuation) = makeStartedModel()
    continuation.yield(payload(event: "$pageview", distinctID: "user-alpha"))
    continuation.yield(payload(event: "purchase", distinctID: "Beta-9"))
    continuation.yield(payload(event: "$autocapture", distinctID: "gamma"))
    await drain { model.rows.count == 3 }

    model.filter = "PAGE"
    #expect(model.visibleRows.map(\.event) == ["$pageview"])
    model.filter = "beta"
    #expect(model.visibleRows.map(\.event) == ["purchase"])
    model.filter = "zzz"
    #expect(model.visibleRows.isEmpty)
    model.filter = ""
    #expect(model.visibleRows.count == 3)
  }

  @Test func streamEndOrErrorMarksConnectionDropped() async {
    let (endedModel, endedContinuation) = makeStartedModel()
    endedContinuation.yield(payload(event: "only", distinctID: "user"))
    await drain { endedModel.rows.count == 1 }
    #expect(endedModel.connectionState == .live)
    endedContinuation.finish()
    await drain { endedModel.connectionState == .dropped }

    let (failedModel, failedContinuation) = makeStartedModel()
    failedContinuation.finish(throwing: URLError(.networkConnectionLost))
    await drain { failedModel.connectionState == .dropped }
  }
}
