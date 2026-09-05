import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Runs a server-side video render: create the export, poll until the file
/// exists, download it to a temp `.mp4` the share sheet can hand out.
@MainActor
@Observable
public final class ReplayExportModel {
  public enum State: Equatable {
    case idle
    case rendering
    case ready(URL)
    case failed(String)
  }

  public private(set) var state: State = .idle

  private let context: ProjectContext
  private let sessionID: String
  private let pollInterval: Duration
  private let timeout: Duration

  public init(
    context: ProjectContext,
    sessionID: String,
    pollInterval: Duration = .seconds(2),
    timeout: Duration = .seconds(90)
  ) {
    self.context = context
    self.sessionID = sessionID
    self.pollInterval = pollInterval
    self.timeout = timeout
  }

  public func export() async {
    guard state != .rendering else { return }
    state = .rendering
    do {
      let exportID = try await context.client.createRecordingExport(
        projectID: context.projectID,
        sessionID: sessionID
      )
      guard try await pollUntilRendered(exportID: exportID) else {
        state = .failed("Couldn't render the video. Try again in a moment.")
        return
      }
      let path = context.client.exportContentPath(projectID: context.projectID, exportID: exportID)
      let data = try await context.client.sendRaw(.get(path))
      let fileURL = try Self.writeTemporaryVideo(data, sessionID: sessionID)
      state = .ready(fileURL)
    } catch {
      PHLog.api.error("recording export failed: \(error)")
      state = .failed("Couldn't render the video. Try again in a moment.")
    }
  }

  /// True once the export has content; false when it reports an exception or
  /// the deadline passes first.
  private func pollUntilRendered(exportID: Int) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
      let status = try await context.client.exportStatus(
        projectID: context.projectID,
        exportID: exportID
      )
      if let exception = status.exception, !exception.isEmpty {
        PHLog.api.error("recording export errored server-side: \(exception)")
        return false
      }
      if status.hasContent { return true }
      guard ContinuousClock.now < deadline else { return false }
      try await Task.sleep(for: pollInterval)
    }
  }

  private static func writeTemporaryVideo(_ data: Data, sessionID: String) throws -> URL {
    let safeName = sessionID.replacingOccurrences(
      of: "[^A-Za-z0-9._-]",
      with: "-",
      options: .regularExpression
    )
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("posthog-recording-\(safeName)")
      .appendingPathExtension("mp4")
    try data.write(to: url, options: .atomic)
    return url
  }
}
