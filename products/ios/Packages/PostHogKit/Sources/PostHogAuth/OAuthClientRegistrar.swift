import Foundation
import PostHogAPI
import PostHogFoundation

/// Resolves the OAuth client id to use for an instance.
///
/// Known instances ship one. Anything else registers its own through RFC 7591
/// dynamic client registration, which PostHog exposes unauthenticated, so a
/// self-hosted instance needs nothing set up by hand. A client id is not a
/// secret (this is a public PKCE client), but it is cached so an install
/// registers at most once per instance.
/// `@unchecked` only because `UserDefaults` predates `Sendable`; it is
/// documented as thread-safe, and nothing else here is mutable.
public struct OAuthClientRegistrar: @unchecked Sendable {
  public enum RegistrationError: Error, Sendable, Equatable {
    case network
    /// The instance refused the registration; its body is worth showing.
    case rejected(status: Int, detail: String?)
  }

  private let transport: HTTPTransport
  private let defaults: UserDefaults

  public init(transport: HTTPTransport = URLSessionTransport(), defaults: UserDefaults = .standard) {
    self.transport = transport
    self.defaults = defaults
  }

  static func cacheKey(for region: Region) -> String {
    "oauth.clientID.\(region.storageKey)"
  }

  public func clientID(for region: Region) async throws -> String {
    if let shipped = AuthConfiguration.preregisteredClientID(for: region) {
      return shipped
    }
    if let cached = defaults.string(forKey: Self.cacheKey(for: region)), !cached.isEmpty {
      return cached
    }
    let registered = try await register(region: region)
    defaults.set(registered, forKey: Self.cacheKey(for: region))
    return registered
  }

  /// Drops a cached registration so the next sign-in registers again. Used when
  /// an instance no longer recognizes the id it gave us.
  public func forget(region: Region) {
    defaults.removeObject(forKey: Self.cacheKey(for: region))
  }

  private func register(region: Region) async throws -> String {
    var request = URLRequest(url: region.apiBaseURL.appending(path: "/oauth/register/"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    // The instance rejects a client_name starting with "posthog", so this one
    // leads with the platform.
    let body: JSONValue = [
      "client_name": "iOS client for PostHog",
      "redirect_uris": [.string(AuthConfiguration.redirectURI)],
      "grant_types": ["authorization_code", "refresh_token"],
      "response_types": ["code"],
      "token_endpoint_auth_method": "none",
    ]
    request.httpBody = try? JSONEncoder().encode(body)

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch {
      throw RegistrationError.network
    }
    guard (200..<300).contains(response.statusCode) else {
      let detail = String(bytes: data, encoding: .utf8)
      PHLog.auth.error("client registration refused: \(response.statusCode)")
      throw RegistrationError.rejected(status: response.statusCode, detail: detail)
    }
    guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: data),
      let clientID = parsed["client_id"]?.stringValue, !clientID.isEmpty
    else {
      throw RegistrationError.rejected(status: response.statusCode, detail: "no client_id in response")
    }
    return clientID
  }
}
