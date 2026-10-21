import Foundation
import PostHogAPI

/// How a stored session authenticates. Cloud regions use OAuth; self-hosted
/// instances use a personal API key (no refresh, no expiry).
public enum AuthMethod: String, Codable, Sendable {
  case oauth
  case personalAPIKey
}

/// Everything the app persists about a signed-in session — one Keychain blob.
public struct StoredSession: Codable, Sendable, Equatable {
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: Date
  public var region: Region
  public var scopeVersion: Int
  public var scopedTeams: [Int]
  public var selectedProjectID: Int?
  public var selectedOrganizationID: String?
  /// Optional so blobs written before self-hosted support still decode.
  public var authMethod: AuthMethod?
  /// The OAuth client the tokens were issued to, so refresh presents the same
  /// one. Absent for API-key sessions and for blobs written before the app
  /// could register its own client.
  public var clientID: String?

  public var isPersonalAPIKey: Bool { authMethod == .personalAPIKey }

  public init(
    accessToken: String,
    refreshToken: String,
    expiresAt: Date,
    region: Region,
    scopeVersion: Int,
    scopedTeams: [Int],
    selectedProjectID: Int? = nil,
    selectedOrganizationID: String? = nil,
    authMethod: AuthMethod? = .oauth,
    clientID: String? = nil
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.region = region
    self.scopeVersion = scopeVersion
    self.scopedTeams = scopedTeams
    self.selectedProjectID = selectedProjectID
    self.selectedOrganizationID = selectedOrganizationID
    self.authMethod = authMethod
    self.clientID = clientID
  }

  /// Keeps the selected project when still authorized, else falls back to the
  /// first scoped team (mirrors the RN app's resolveActiveProjectId).
  public func resolvingSelectedProject() -> StoredSession {
    var session = self
    if let selected = session.selectedProjectID, session.scopedTeams.contains(selected) {
      return session
    }
    // An empty scoped_teams list means org-wide access; keep the selection.
    if session.scopedTeams.isEmpty {
      return session
    }
    session.selectedProjectID = session.scopedTeams.first
    return session
  }
}
