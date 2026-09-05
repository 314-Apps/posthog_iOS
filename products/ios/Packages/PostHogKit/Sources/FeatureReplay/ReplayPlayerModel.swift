import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Bootstraps the embedded player from a share the recording already has.
///
/// It never creates one. An enabled share serves the recording to anyone with
/// the link and no login, so a recording that is not already shared stays
/// unplayable here rather than being published to make it play.
@MainActor
@Observable
public final class ReplayPlayerModel {
  public enum State: Equatable, Sendable {
    case loading
    case ready(URL)
    /// This recording has no share to play through.
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
      let sharing = try await context.client.recordingSharing(
        projectID: context.projectID,
        sessionID: sessionID
      )
      guard sharing.enabled, let token = sharing.accessToken,
        let url = Self.embedURL(region: context.region, token: token)
      else {
        state = .unavailable
        return
      }
      state = .ready(url)
    } catch let error as APIError {
      PHLog.api.error("recording share lookup failed: \(error)")
      state = hasNoShareToRead(error) ? .unavailable : .failed
    } catch {
      PHLog.api.error("recording share lookup failed: \(error)")
      state = .failed
    }
  }

  /// A 4xx says this session has no share the caller may read, whatever the
  /// reason. Anything else is transient and keeps the retry path.
  private func hasNoShareToRead(_ error: APIError) -> Bool {
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
