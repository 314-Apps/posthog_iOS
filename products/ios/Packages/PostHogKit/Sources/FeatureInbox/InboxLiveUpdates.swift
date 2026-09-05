import Foundation
import PostHogAPI

/// Pokes the inbox when the live endpoint reports notification activity.
/// Yields one Void per server event; coalescing and refetching belong to the
/// consumer, as does reconnection when the stream finishes.
public struct InboxLiveUpdates: Sendable {
  private let liveURL: URL
  private let token: String
  private let sse: SSEClient

  public init(liveURL: URL, token: String, sse: SSEClient = SSEClient()) {
    self.liveURL = liveURL
    self.token = token
    self.sse = sse
  }

  public func pokes() -> AsyncStream<Void> {
    let events = sse.events(
      url: liveURL.appending(path: "/notifications"),
      headers: ["Authorization": "Bearer \(token)"]
    )
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let task = Task {
      do {
        for try await _ in events {
          continuation.yield()
        }
      } catch {
        // A failed stream just finishes; the consumer owns reconnection.
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
