import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// One rendered chart in the transcript. The query travels alongside the
/// result so `InsightRenderer` can pick display variants.
public struct MaxViz: Sendable, Equatable {
  public let query: DataQuery?
  public let result: QueryResult

  public init(query: DataQuery?, result: QueryResult) {
    self.query = query
    self.result = result
  }
}

/// One transcript entry.
public struct MaxMessage: Sendable, Equatable, Identifiable {
  public let id: String
  public let role: MaxRole
  public var text: String
  public var visualization: MaxViz?

  public init(id: String, role: MaxRole, text: String, visualization: MaxViz? = nil) {
    self.id = id
    self.role = role
    self.text = text
    self.visualization = visualization
  }
}

/// Drives one Max conversation: appends the user's turn, opens the SSE
/// stream, and folds streamed frames into the transcript. The stream factory
/// is injected so tests pump events without a network.
@MainActor
@Observable
public final class MaxChatModel {
  public typealias StreamFactory =
    @Sendable (MaxStreamRequest) -> AsyncThrowingStream<ServerSentEvent, Error>

  public private(set) var messages: [MaxMessage] = []
  public private(set) var isStreaming = false
  public private(set) var errorText: String?
  public private(set) var conversationTitle: String?

  let context: ProjectContext
  private let tokenProvider: TokenProviding
  private let streamFactory: StreamFactory
  /// Minted on first send so every later turn continues the same conversation.
  private var conversationID: UUID?
  private var streamTask: Task<Void, Never>?
  /// Transcript id for streamed assistant frames that carry no id of their own.
  private var inFlightAssistantID = UUID().uuidString

  public init(
    context: ProjectContext,
    tokenProvider: TokenProviding,
    streamFactory: @escaping StreamFactory = { request in
      SSEClient().events(url: request.url, headers: request.headers, method: "POST", body: request.body)
    }
  ) {
    self.context = context
    self.tokenProvider = tokenProvider
    self.streamFactory = streamFactory
  }

  public func send(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isStreaming else { return }
    errorText = nil
    messages.append(MaxMessage(id: UUID().uuidString, role: .user, text: trimmed))
    let conversation = conversationID ?? UUID()
    conversationID = conversation
    inFlightAssistantID = UUID().uuidString
    isStreaming = true
    streamTask = Task { [weak self] in
      await self?.stream(message: trimmed, conversation: conversation)
    }
  }

  public func stop() {
    streamTask?.cancel()
    streamTask = nil
    isStreaming = false
  }

  private func stream(message: String, conversation: UUID) async {
    do {
      let token = try await tokenProvider.validAccessToken()
      let request = MaxStreamRequest(
        baseURL: context.region.apiBaseURL,
        projectID: context.projectID,
        accessToken: token,
        conversationID: conversation,
        message: message
      )
      for try await event in streamFactory(request) {
        handle(MaxStreamEvent.parse(event))
      }
      isStreaming = false
    } catch {
      guard !Task.isCancelled else { return }
      PHLog.sse.error("max stream failed: \(error)")
      errorText = "Max couldn't answer. Try again."
      isStreaming = false
    }
  }

  private func handle(_ event: MaxStreamEvent) {
    switch event {
    case .message(let role, let id, let content):
      applyMessage(role: role, id: id, content: content)
    case .visualization(let query, let answerBody):
      appendVisualization(query: query, answerBody: answerBody)
    case .conversationUpdate(_, let title):
      if let title {
        conversationTitle = title
      }
    case .ignored:
      break
    }
  }

  private func applyMessage(role: MaxRole, id: String?, content: String) {
    switch role {
    case .user:
      // The server echoes the human turn; the local append already covered it.
      guard !messages.contains(where: { $0.role == .user && $0.text == content }) else { return }
      messages.append(MaxMessage(id: id ?? UUID().uuidString, role: .user, text: content))
    case .assistant:
      let messageID = id ?? inFlightAssistantID
      if let index = messages.firstIndex(where: { $0.id == messageID }) {
        // Streamed content is cumulative, so each frame replaces the text whole.
        messages[index].text = content
      } else {
        messages.append(MaxMessage(id: messageID, role: .assistant, text: content))
      }
    }
  }

  private func appendVisualization(query: DataQuery?, answerBody: JSONValue) {
    let result: QueryResult
    if let kind = query?.renderSource.kind ?? answerBody["kind"]?.stringValue {
      result = QueryResult.parse(kind: kind, body: answerBody)
    } else {
      result = .unknown(answerBody)
    }
    messages.append(
      MaxMessage(
        id: UUID().uuidString,
        role: .assistant,
        text: "",
        visualization: MaxViz(query: query, result: result)
      )
    )
  }
}
