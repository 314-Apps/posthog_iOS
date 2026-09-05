import Foundation
import Observation
import PostHogAPI
import PostHogFoundation

/// Drives the live events tail: decodes stream payloads, keeps the newest
/// rows, buffers while paused, and reports connection health. The stream
/// factory is injected so tests pump events without a network.
@MainActor
@Observable
public final class LiveFeedModel {
  public enum ConnectionState: Sendable, Equatable {
    case connecting
    case live
    case dropped
  }

  /// Row cap; the oldest rows drop first so memory stays bounded on busy projects.
  public static let maxRows = 500

  public private(set) var rows: [LiveEvent] = []
  public private(set) var connectionState: ConnectionState = .connecting
  public private(set) var isPaused = false
  public private(set) var bufferedCount = 0
  public var filter = ""

  private var buffered: [LiveEvent] = []
  private var streamTask: Task<Void, Never>?
  private let events: () -> AsyncThrowingStream<ServerSentEvent, Error>
  private let now: () -> Date

  public init(
    events: @escaping () -> AsyncThrowingStream<ServerSentEvent, Error>,
    now: @escaping () -> Date = { .now }
  ) {
    self.events = events
    self.now = now
  }

  public var visibleRows: [LiveEvent] {
    guard !filter.isEmpty else { return rows }
    return rows.filter {
      $0.event.localizedCaseInsensitiveContains(filter)
        || $0.distinctID.localizedCaseInsensitiveContains(filter)
    }
  }

  /// True while a stream task exists, including one that already ended in
  /// `.dropped`; a dropped feed restarts through retry, not the scene phase.
  public var isStreaming: Bool { streamTask != nil }

  public func start() {
    stop()
    connectionState = .connecting
    let stream = events()
    streamTask = Task { [weak self] in
      do {
        for try await message in stream {
          self?.receive(message)
        }
      } catch {}
      // A cancelled task is a deliberate stop; only a server-side end or error is a drop.
      guard !Task.isCancelled else { return }
      self?.connectionState = .dropped
    }
  }

  public func stop() {
    streamTask?.cancel()
    streamTask = nil
  }

  public func pause() {
    isPaused = true
  }

  public func resume() {
    guard isPaused else { return }
    isPaused = false
    rows.insert(contentsOf: buffered.reversed(), at: 0)
    trimRows()
    buffered.removeAll()
    bufferedCount = 0
  }

  /// Relative label for a row; events that arrive without a timestamp read as current.
  public func timeLabel(for event: LiveEvent) -> String {
    guard let timestamp = event.timestamp else { return "now" }
    return RelativeDateFormat.ago(timestamp, relativeTo: now())
  }

  private func receive(_ message: ServerSentEvent) {
    if connectionState != .live {
      connectionState = .live
    }
    guard let event = LiveEvent(sseData: message.data) else { return }
    if isPaused {
      buffered.append(event)
      // The buffer honors the same cap so a long pause cannot grow unbounded.
      if buffered.count > Self.maxRows {
        buffered.removeFirst(buffered.count - Self.maxRows)
      }
      bufferedCount = buffered.count
    } else {
      rows.insert(event, at: 0)
      trimRows()
    }
  }

  private func trimRows() {
    if rows.count > Self.maxRows {
      rows.removeLast(rows.count - Self.maxRows)
    }
  }
}
