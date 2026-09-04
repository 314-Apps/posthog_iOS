import Foundation

/// Supplies bearer tokens to the transport layer.
///
/// `PostHogAuth.TokenBroker` is the production conformance; tests inject stubs.
/// Defined here (not in PostHogAuth) so the API layer never imports auth.
public protocol TokenProviding: Sendable {
  /// A currently-valid access token, refreshing first if needed.
  func validAccessToken() async throws -> String

  /// Force a refresh after a 401, returning the new token.
  /// Throws `TokenRefreshError.authFailure` when the session is terminally dead.
  func refreshedAccessToken() async throws -> String
}

/// Classified refresh failures. Only `.authFailure` may sign the user out.
public enum TokenRefreshError: Error, Sendable, Equatable {
  /// 401/403, or a 400 whose body `error` is `invalid_grant`/`invalid_token` — the session is dead.
  case authFailure(detail: String)
  /// 5xx — server trouble; keep the session.
  case serverError(status: Int)
  /// Transport failure; keep the session.
  case network
  /// Anything else (e.g. `invalid_client` config bugs); keep the session.
  case unknown(detail: String)
}
