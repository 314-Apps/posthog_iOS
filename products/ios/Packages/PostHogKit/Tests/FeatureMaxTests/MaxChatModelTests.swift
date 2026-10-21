import Foundation
import PostHogAPI
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureMax

/// Hands the model pre-scripted streams and records every request it opens.
private final class StreamHub: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [AsyncThrowingStream<ServerSentEvent, Error>] = []
  private var recorded: [MaxStreamRequest] = []

  var requests: [MaxStreamRequest] { lock.withLock { recorded } }

  func enqueue() -> AsyncThrowingStream<ServerSentEvent, Error>.Continuation {
    let (stream, continuation) = AsyncThrowingStream<ServerSentEvent, Error>.makeStream()
    lock.withLock { pending.append(stream) }
    return continuation
  }

  func open(_ request: MaxStreamRequest) -> AsyncThrowingStream<ServerSentEvent, Error> {
    lock.withLock {
      recorded.append(request)
      guard !pending.isEmpty else {
        return AsyncThrowingStream { $0.finish() }
      }
      return pending.removeFirst()
    }
  }
}

@MainActor
@Suite struct MaxChatModelTests {
  private func makeModel() -> (MaxChatModel, StreamHub) {
    let hub = StreamHub()
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: StubTransport(script: []),
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("max-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    let model = MaxChatModel(
      context: context,
      tokenProvider: StubTokens(),
      streamFactory: { hub.open($0) }
    )
    return (model, hub)
  }

  private func aiFrame(id: String, content: String) -> ServerSentEvent {
    ServerSentEvent(event: "message", data: #"{"type":"ai","id":"\#(id)","content":"\#(content)"}"#)
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

  private func conversationField(of request: MaxStreamRequest) -> String? {
    let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: String]
    return json?["conversation"]
  }

  @Test func sendAppendsUserTurnAndReplacesAssistantTextByID() async {
    let (model, hub) = makeModel()
    let continuation = hub.enqueue()
    model.send("hello")

    #expect(model.messages.map(\.text) == ["hello"])
    #expect(model.messages[0].role == .user)
    #expect(model.isStreaming)

    continuation.yield(aiFrame(id: "m1", content: "Think"))
    await drain { model.messages.count == 2 }
    continuation.yield(aiFrame(id: "m1", content: "Thinking done"))
    await drain { model.messages.last?.text == "Thinking done" }
    #expect(model.messages.count == 2)
    #expect(model.messages.last?.role == .assistant)

    continuation.yield(aiFrame(id: "m2", content: "Second answer"))
    await drain { model.messages.count == 3 }
    #expect(model.messages.last?.text == "Second answer")

    continuation.finish()
    await drain { !model.isStreaming }
    #expect(model.errorText == nil)
    await drain { !hub.requests.isEmpty }
    #expect(hub.requests[0].headers["Authorization"] == "Bearer pha_valid")
  }

  @Test func doubleSendBlockedWhileStreamingAndConversationIDPersists() async {
    let (model, hub) = makeModel()
    let first = hub.enqueue()
    model.send("one")
    model.send("two")
    #expect(model.messages.count == 1)

    await drain { hub.requests.count == 1 }
    first.finish()
    await drain { !model.isStreaming }

    _ = hub.enqueue()
    model.send("two")
    #expect(model.messages.count == 2)
    await drain { hub.requests.count == 2 }
    let firstConversation = conversationField(of: hub.requests[0])
    #expect(firstConversation != nil)
    #expect(firstConversation == conversationField(of: hub.requests[1]))
  }

  @Test func humanEchoSkippedWhenLocallyPresent() async {
    let (model, hub) = makeModel()
    let continuation = hub.enqueue()
    model.send("hello")

    continuation.yield(
      ServerSentEvent(event: "message", data: #"{"type":"human","id":"h1","content":"hello"}"#))
    continuation.yield(
      ServerSentEvent(event: "message", data: #"{"type":"human","id":"h2","content":"replayed turn"}"#))
    await drain { model.messages.count == 2 }
    #expect(model.messages.map(\.text) == ["hello", "replayed turn"])
    #expect(model.messages.allSatisfy { $0.role == .user })
  }

  @Test func streamErrorSetsErrorTextAndKeepsTranscript() async {
    let (model, hub) = makeModel()
    let continuation = hub.enqueue()
    model.send("hello")

    continuation.yield(aiFrame(id: "m1", content: "Partial answer"))
    await drain { model.messages.count == 2 }
    continuation.finish(throwing: URLError(.networkConnectionLost))
    await drain { model.errorText != nil }

    #expect(model.errorText == "Max couldn't answer. Try again.")
    #expect(model.messages.map(\.text) == ["hello", "Partial answer"])
    #expect(!model.isStreaming)
  }

  @Test func vizFrameLandsAsCardMessage() async {
    let (model, hub) = makeModel()
    let continuation = hub.enqueue()
    model.send("chart signups")

    let data = """
      {"type": "ai/viz", "answer": {
        "query": {"kind": "TrendsQuery", "series": [{"kind": "EventsNode"}]},
        "results": [{"label": "signups", "data": [1, 2, 3]}]
      }}
      """
    continuation.yield(ServerSentEvent(event: "message", data: data))
    await drain { model.messages.count == 2 }

    let viz = model.messages.last?.visualization
    #expect(viz?.query?.kind == "TrendsQuery")
    guard case .series(let series) = viz?.result else {
      Issue.record("expected a series result, got \(String(describing: viz?.result))")
      return
    }
    #expect(series.map(\.label) == ["signups"])
    #expect(series[0].data == [1, 2, 3])
  }

  @Test func stopCancelsTheStreamAndUnblocksSending() async {
    let (model, hub) = makeModel()
    _ = hub.enqueue()
    model.send("hello")
    await drain { hub.requests.count == 1 }

    model.stop()
    #expect(!model.isStreaming)
    #expect(model.errorText == nil)

    _ = hub.enqueue()
    model.send("again")
    #expect(model.messages.count == 2)
    await drain { hub.requests.count == 2 }
  }
}
