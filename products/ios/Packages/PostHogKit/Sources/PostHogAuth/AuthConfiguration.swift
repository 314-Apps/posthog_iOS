import Foundation
import PostHogAPI

/// OAuth client configuration per region.
///
/// The app is a public client (PKCE, no secret). Client IDs come from the
/// first-party OAuth app registered per region (staff-registered; see
/// products/ios/docs/LOCAL-DEVELOPMENT.md for the dev flow).
public struct AuthConfiguration: Sendable {
  public let region: Region
  public let clientID: String

  public init(region: Region, clientID: String) {
    self.region = region
    self.clientID = clientID
  }

  /// Bump when `scopes` changes: a stored session with an older version is
  /// silently discarded on launch so the user re-authorizes with the new set.
  public static let scopeVersion = 2

  /// Everything Phases 1-4 read or control, limited to scopes that exist
  /// server-side today. `user:write` covers push-token registration later.
  public static let scopes: [String] = [
    "user:read", "user:write",
    "organization:read", "project:read",
    "query:read",
    "insight:read", "dashboard:read",
    "feature_flag:read", "feature_flag:write",
    "activity_log:read",
    "session_recording:read",
    "error_tracking:read", "error_tracking:write",
    "experiment:read", "survey:read",
    "annotation:read", "annotation:write",
    "alert:read", "alert:write",
    "person:read", "cohort:read",
    "conversation:write",
    "export:read", "export:write",
  ]

  public static let redirectURI = "posthog-ios://oauth/callback"
  public static let callbackScheme = "posthog-ios"

  /// Public OAuth client ids, one per known instance. These are not secrets:
  /// a native app is a public client, so it holds no credential and relies on
  /// PKCE. The cloud ids were minted through dynamic client registration and
  /// should be replaced by staff-registered first-party apps, which would also
  /// retire the consent screen. Unknown instances have no id and register one.
  public static func preregisteredClientID(for region: Region) -> String? {
    switch region {
    case .us: "8dMUWoLwEH6i52NHfhvNnNT8ziXxiPoUpzv5HY8Y"
    case .eu: "oyaORiYYpIRRAa4K1rN0Z9l9ux0dkaM3Dv3zpRqo"
    // The local-dev-only demo app every PostHog client shares.
    case .dev: "DC5uRLVbGI02YQ82grxgnK6Qn12SXWpCqdPb60oZ"
    case .selfHosted: nil
    }
  }

  public var authorizeURL: URL {
    region.apiBaseURL.appending(path: "/oauth/authorize/")
  }

  public var tokenURL: URL {
    region.apiBaseURL.appending(path: "/oauth/token/")
  }

  public var revokeURL: URL {
    region.apiBaseURL.appending(path: "/oauth/revoke/")
  }

  /// The full authorize request. `required_access_level=project` makes the
  /// server scope the token to projects the user picks (mirrors the RN app).
  public func makeAuthorizeURL(pkce: PKCEPair, state: String) -> URL {
    var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
      URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: pkce.challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "required_access_level", value: "project"),
    ]
    return components.url!
  }
}
