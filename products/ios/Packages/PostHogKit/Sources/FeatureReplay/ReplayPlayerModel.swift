import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Bootstraps the embedded player: reads the recording's sharing state,
/// enables it when it is off, and builds the `/embedded/<token>` URL.
@MainActor
@Observable
public final class ReplayPlayerModel {
  public enum State: Equatable, Sendable {
    case loading
    case ready(URL)
    /// The organization forbids public sharing, so embedding cannot work.
    case unavailable
    case failed
  }

  public private(set) var state: State = .loading

  private let context: ProjectContext
  private let sessionID: String

  public init(context: ProjectContext, sessionID: String) {
    self.context = context
    self.sessionID = sessionID
  }

  public func load() async {
    state = .loading
    do {
      var sharing = try await context.client.recordingSharing(
        projectID: context.projectID,
        sessionID: sessionID
      )
      if !sharing.enabled {
        sharing = try await context.client.enableRecordingSharing(
          projectID: context.projectID,
          sessionID: sessionID
        )
      }
      guard sharing.enabled, let token = sharing.accessToken,
        let url = Self.embedURL(region: context.region, token: token)
      else {
        state = .unavailable
        return
      }
      state = .ready(url)
    } catch let error as APIError {
      PHLog.api.error("recording sharing bootstrap failed: \(error)")
      state = isSharingForbidden(error) ? .unavailable : .failed
    } catch {
      PHLog.api.error("recording sharing bootstrap failed: \(error)")
      state = .failed
    }
  }

  /// A 4xx means the org's security settings turned public sharing off; other
  /// failures are transient and keep the retry path.
  private func isSharingForbidden(_ error: APIError) -> Bool {
    if case .server(let status, _, _, _) = error {
      return (400..<500).contains(status)
    }
    return false
  }

  static func embedURL(region: Region, token: String) -> URL? {
    let base = region.apiBaseURL.appending(path: "/embedded/\(token)")
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      return nil
    }
    // Value-less items render as "?whitelabel&noHeader", which the embed page expects.
    components.queryItems = [
      URLQueryItem(name: "whitelabel", value: nil),
      URLQueryItem(name: "noHeader", value: nil),
    ]
    return components.url
  }
}
