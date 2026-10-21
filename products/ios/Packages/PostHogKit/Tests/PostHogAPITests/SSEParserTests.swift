import Foundation
import Testing

@testable import PostHogAPI

@Suite struct SSEParserTests {
  private func parse(_ raw: String) -> [ServerSentEvent] {
    var parser = SSEParser()
    var events: [ServerSentEvent] = []
    for byte in Array(raw.utf8) {
      if let event = parser.feed(byte) {
        events.append(event)
      }
    }
    return events
  }

  @Test func parsesSimpleEvent() {
    let events = parse("event: message\ndata: {\"x\":1}\n\n")
    #expect(events == [ServerSentEvent(event: "message", data: "{\"x\":1}")])
  }

  @Test func joinsMultiLineData() {
    let events = parse("data: line one\ndata: line two\n\n")
    #expect(events.count == 1)
    #expect(events[0].data == "line one\nline two")
  }

  @Test func dropsKeepaliveComments() {
    let events = parse(": keepalive\n\n: keepalive\n\ndata: real\n\n")
    #expect(events == [ServerSentEvent(data: "real")])
  }

  @Test func handlesCRLF() {
    let events = parse("event: status\r\ndata: ok\r\n\r\n")
    #expect(events == [ServerSentEvent(event: "status", data: "ok")])
  }

  @Test func carriesIDAndRetry() {
    let events = parse("id: 42\nretry: 3000\ndata: a\n\ndata: b\n\n")
    #expect(events.count == 2)
    #expect(events[0].id == "42")
    #expect(events[0].retryMilliseconds == 3000)
    // The last seen id sticks across events, per spec.
    #expect(events[1].id == "42")
  }

  @Test func blankLineWithoutDataEmitsNothing() {
    let events = parse("event: ping\n\n")
    #expect(events.isEmpty)
  }

  @Test func handlesValueWithoutSpaceAfterColon() {
    let events = parse("data:tight\n\n")
    #expect(events == [ServerSentEvent(data: "tight")])
  }

  @Test func partialChunksAcrossFeedsAccumulate() {
    var parser = SSEParser()
    var events: [ServerSentEvent] = []
    let chunks = ["da", "ta: sp", "lit\n", "\n"]
    for chunk in chunks {
      for byte in Array(chunk.utf8) {
        if let event = parser.feed(byte) {
          events.append(event)
        }
      }
    }
    #expect(events == [ServerSentEvent(data: "split")])
  }
}
