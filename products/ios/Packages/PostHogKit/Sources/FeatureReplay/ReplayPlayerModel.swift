import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Drives playback of one recording.
///
/// The data comes from the authenticated snapshots API and is drawn by a player
/// that ships inside the app, so a recording plays for anyone allowed to watch
/// it. Nothing here reads or creates a public share.
@MainActor
@Observable
public final class ReplayPlayerModel {
  public enum Unavailable: Equatable, Sendable {
    case noAccess
    case noData
    case deleted
    case tooBusy

    /// Says what happened and what the person can do about it.
    public var message: String {
      switch self {
      case .noAccess:
        return "You don't have access to this recording. Ask an admin of this project for access."
      case .noData:
        return "This recording has no data to play. It may have expired or been removed."
      case .deleted:
        return "This recording was deleted and can't be played."
      case .tooBusy:
        return "PostHog is busy right now. Try again in a moment."
      }
    }
  }

  public enum State: Equatable, Sendable {
    case loading
    case ready(chunkCount: Int, isMobile: Bool)
    case unavailable(Unavailable)
    case failed(String)
  }

  public private(set) var state: State = .loading
  public private(set) var loadedChunks = 0
  public private(set) var totalChunks = 0
  public private(set) var duration: Double = 0
  public private(set) var position: Double = 0
  public private(set) var isPlaying = false

  /// Raised so the web view runs each command once.
  public private(set) var command: (id: Int, value: ReplayPlayerCommand)?

  let loader: ReplaySnapshotLoader

  private let context: ProjectContext
  private let sessionID: String
  private var commandCount = 0

  public init(context: ProjectContext, sessionID: String) {
    self.context = context
    self.sessionID = sessionID
    self.loader = ReplaySnapshotLoader(context: context, sessionID: sessionID)
  }

  public func load() async {
    state = .loading
    do {
      let recording = try? await context.client.sessionRecording(
        projectID: context.projectID,
        sessionID: sessionID
      )
      let chunkCount = try await loader.plan()
      totalChunks = chunkCount
      state = .ready(chunkCount: chunkCount, isMobile: recording?.isMobileRecording ?? false)
    } catch let failure as ReplayLoadFailure {
      PHLog.api.error("replay plan failed: \(failure)")
      state = Self.state(for: failure)
    } catch {
      PHLog.api.error("replay plan failed: \(error)")
      state = .failed("Couldn't load this recording. Try again.")
    }
  }

  static func state(for failure: ReplayLoadFailure) -> State {
    switch failure {
    case .noAccess: return .unavailable(.noAccess)
    case .noData: return .unavailable(.noData)
    case .deleted: return .unavailable(.deleted)
    case .tooBusy: return .unavailable(.tooBusy)
    case .other: return .failed("Couldn't load this recording. Try again.")
    }
  }

  public func handle(_ event: ReplayPlayerEvent) {
    switch event {
    case .progress(let loaded, let total):
      loadedChunks = loaded
      totalChunks = max(total, totalChunks)
    case .ready(let duration):
      self.duration = duration
      play()
    case .time(let current):
      position = current
    case .ended:
      isPlaying = false
      position = duration
    case .failed(let message):
      PHLog.api.error("replay player reported: \(message)")
      state = .failed("This recording stopped playing. Try again, or open it on the web.")
    }
  }

  public func play() {
    isPlaying = true
    send(.play)
  }

  public func pause() {
    isPlaying = false
    send(.pause)
  }

  public func togglePlayback() {
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  public func seek(to milliseconds: Double) {
    position = milliseconds
    send(.seek(milliseconds: milliseconds))
  }

  public func setSpeed(_ rate: Double) {
    send(.speed(rate))
  }

  private func send(_ value: ReplayPlayerCommand) {
    commandCount += 1
    command = (id: commandCount, value: value)
  }
}
