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

  public init(region: Region) {
    self.region = region
    self.clientID = Self.clientID(for: region)
  }

  /// Bump when `scopes` changes: a stored session with an older version is
  /// silently discarded on launch so the user re-authorizes with the new set.
  public static let scopeVersion = 1

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
    "sharing_configuration:read",
  ]

  public static let redirectURI = "posthog-ios://oauth/callback"
  public static let callbackScheme = "posthog-ios"

  // Cloud registration of the first-party iOS OAuth apps is an ops step (plan
  // PR-B4); until a region's app exists, sign-in there fails with
  // invalid_client. The dev client is the local-dev-only demo app every
  // PostHog client app shares (public, committed credentials, guarded to
  // DEBUG + non-cloud server-side).
  public static func clientID(for region: Region) -> String {
    switch region {
    case .us: "IOS_CLIENT_ID_US_NOT_REGISTERED"
    case .eu: "IOS_CLIENT_ID_EU_NOT_REGISTERED"
    case .dev: "DC5uRLVbGI02YQ82grxgnK6Qn12SXWpCqdPb60oZ"
    // Self-hosted instances authenticate with a personal API key, never OAuth.
    case .selfHosted: "SELF_HOSTED_USES_PERSONAL_API_KEY"
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
