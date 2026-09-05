import Foundation

/// Builds the create-and-stream request for one Max turn: POSTing to the
/// conversations endpoint returns the answer as SSE. Pure so tests can assert
/// the exact URL, headers, and body without a network.
public struct MaxStreamRequest: Sendable, Equatable {
  public let url: URL
  public let headers: [String: String]
  public let body: Data

  public init(
    baseURL: URL,
    projectID: Int,
    accessToken: String,
    conversationID: UUID,
    message: String,
    traceID: UUID = UUID()
  ) {
    self.url = baseURL.appending(path: "/api/projects/\(projectID)/conversations/")
    self.headers = [
      "Authorization": "Bearer \(accessToken)",
      "Content-Type": "application/json",
      // The endpoint streams events but still offers only a JSON renderer, so
      // asking for event-stream alone is refused before the view ever runs.
      // Naming both gets through content negotiation either way.
      "Accept": "text/event-stream, application/json",
    ]
    let payload: [String: String] = [
      "conversation": conversationID.uuidString.lowercased(),
      "content": message,
      "trace_id": traceID.uuidString.lowercased(),
    ]
    // Sorted keys keep the body byte-stable so tests can assert it whole.
    self.body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
  }
}
