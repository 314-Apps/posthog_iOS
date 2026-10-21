import AuthenticationServices
import Foundation
import PostHogAPI
import PostHogFoundation

public enum SignInError: Error, Sendable {
  case cancelled
  case invalidCallback
  case stateMismatch
  case exchangeFailed(TokenRefreshError)
  /// No OAuth client is shipped for this instance and registering one failed.
  case clientUnavailable
}

/// Drives the OAuth authorization-code + PKCE flow in the system browser.
/// SSO, 2FA, and passkeys all happen inside the ASWebAuthenticationSession —
/// delegating them to the web is the point of using OAuth here.
@MainActor
public final class AuthService {
  private let transport: HTTPTransport
  private let registrar: OAuthClientRegistrar
  private let contextProvider = PresentationContextProvider()

  public init(
    transport: HTTPTransport = URLSessionTransport(),
    registrar: OAuthClientRegistrar? = nil
  ) {
    self.transport = transport
    self.registrar = registrar ?? OAuthClientRegistrar(transport: transport)
  }

  /// Runs the browser flow for a region and returns a ready session.
  /// Non-ephemeral on purpose: shared Safari cookies let an already-signed-in
  /// user skip credentials, and first-party apps skip the consent screen.
  public func signIn(region: Region) async throws -> StoredSession {
    let clientID: String
    do {
      clientID = try await registrar.clientID(for: region)
    } catch {
      PHLog.auth.error("could not resolve an OAuth client: \(error)")
      throw SignInError.clientUnavailable
    }
    let configuration = AuthConfiguration(region: region, clientID: clientID)
    let pkce = PKCEPair()
    let state = PKCEPair.base64URLEncode(Data((0..<24).map { _ in UInt8.random(in: 0...255) }))
    let authorizeURL = configuration.makeAuthorizeURL(pkce: pkce, state: state)

    let callback = try await runWebSession(url: authorizeURL)
    let code = try Self.parseCallback(callback, expectedState: state)
    return try await exchange(code: code, pkce: pkce, configuration: configuration)
  }

  /// Best-effort revocation, then the caller wipes local state.
  public func revoke(session: StoredSession) async {
    guard
      let clientID = session.clientID
        ?? AuthConfiguration.preregisteredClientID(for: session.region)
    else { return }
    let configuration = AuthConfiguration(region: session.region, clientID: clientID)
    for token in [session.refreshToken, session.accessToken] {
      let request = TokenEndpoint.makeRequest(
        url: configuration.revokeURL,
        fields: [("token", token), ("client_id", configuration.clientID)]
      )
      _ = try? await transport.send(request)
    }
  }

  // MARK: Steps

  private func runWebSession(url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: AuthConfiguration.callbackScheme
      ) { callbackURL, error in
        if let callbackURL {
          continuation.resume(returning: callbackURL)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          continuation.resume(throwing: SignInError.cancelled)
        } else {
          continuation.resume(throwing: error ?? SignInError.invalidCallback)
        }
      }
      session.presentationContextProvider = contextProvider
      session.prefersEphemeralWebBrowserSession = false
      session.start()
    }
  }

  nonisolated static func parseCallback(_ url: URL, expectedState: String) throws -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw SignInError.invalidCallback
    }
    let items = components.queryItems ?? []
    guard let code = items.first(where: { $0.name == "code" })?.value else {
      throw SignInError.invalidCallback
    }
    guard items.first(where: { $0.name == "state" })?.value == expectedState else {
      throw SignInError.stateMismatch
    }
    return code
  }

  private func exchange(
    code: String,
    pkce: PKCEPair,
    configuration: AuthConfiguration
  ) async throws -> StoredSession {
    let request = TokenEndpoint.makeRequest(
      url: configuration.tokenURL,
      fields: [
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", AuthConfiguration.redirectURI),
        ("client_id", configuration.clientID),
        ("code_verifier", pkce.verifier),
      ]
    )

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch {
      throw SignInError.exchangeFailed(.network)
    }
    guard (200..<300).contains(response.statusCode) else {
      throw SignInError.exchangeFailed(
        TokenEndpoint.classifyFailure(status: response.statusCode, body: data)
      )
    }
    guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
      throw SignInError.exchangeFailed(.unknown(detail: "token_decode_failed"))
    }

    let session = StoredSession(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken,
      expiresAt: Date.now.addingTimeInterval(token.expiresIn),
      region: configuration.region,
      scopeVersion: AuthConfiguration.scopeVersion,
      scopedTeams: token.scopedTeams ?? [],
      authMethod: .oauth,
      clientID: configuration.clientID
    )
    return session.resolvingSelectedProject()
  }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    ASPresentationAnchor()
  }
}
