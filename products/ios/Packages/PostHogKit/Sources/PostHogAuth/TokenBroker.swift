import Foundation
import PostHogAPI
import PostHogFoundation

/// Events the app shell reacts to.
public enum AuthEvent: Sendable, Equatable {
  /// The refresh token is terminally dead — flip to signed-out.
  case sessionInvalidated
}

/// Single-flight token authority. Every access token the app uses flows through
/// here; concurrent callers share one refresh, which (with the server's 2-minute
/// rotation grace) eliminates refresh-token reuse races.
public actor TokenBroker: TokenProviding {
  /// Refresh this long before nominal expiry (access tokens live 1 hour).
  static let expiryBuffer: TimeInterval = 300

  private var session: StoredSession?
  private var refreshTask: Task<StoredSession, Error>?
  private let storage: SessionStorage
  private let transport: HTTPTransport
  private let events: AsyncStream<AuthEvent>.Continuation

  /// The app shell consumes this to observe terminal sign-outs.
  public nonisolated let authEvents: AsyncStream<AuthEvent>

  public init(
    storage: SessionStorage,
    transport: HTTPTransport = URLSessionTransport(),
    session: StoredSession? = nil
  ) {
    self.storage = storage
    self.transport = transport
    self.session = session ?? storage.load()
    let (stream, continuation) = AsyncStream<AuthEvent>.makeStream()
    self.authEvents = stream
    self.events = continuation
  }

  public var currentSession: StoredSession? { session }

  /// A fresh sign-in or an updated project selection.
  public func adopt(_ newSession: StoredSession) {
    session = newSession
    storage.save(newSession)
  }

  public func clear() {
    session = nil
    refreshTask?.cancel()
    refreshTask = nil
    storage.clear()
  }

  // MARK: TokenProviding

  public func validAccessToken() async throws -> String {
    guard let session else {
      throw TokenRefreshError.authFailure(detail: "no_session")
    }
    // Personal API keys never refresh; they are valid until revoked.
    if session.isPersonalAPIKey {
      return session.accessToken
    }
    if session.expiresAt.timeIntervalSinceNow > Self.expiryBuffer {
      return session.accessToken
    }
    return try await refresh().accessToken
  }

  public func refreshedAccessToken() async throws -> String {
    // A 401 on a personal API key means it was revoked — terminal.
    if let session, session.isPersonalAPIKey {
      self.session = nil
      storage.clear()
      events.yield(.sessionInvalidated)
      throw TokenRefreshError.authFailure(detail: "personal_api_key_revoked")
    }
    return try await refresh().accessToken
  }

  // MARK: Refresh

  private func refresh() async throws -> StoredSession {
    if let running = refreshTask {
      return try await running.value
    }
    guard let current = session else {
      throw TokenRefreshError.authFailure(detail: "no_session")
    }
    let task = Task<StoredSession, Error> { [transport] in
      try await Self.performRefresh(current: current, transport: transport)
    }
    refreshTask = task
    defer { refreshTask = nil }

    do {
      let refreshed = try await task.value
      // Persist rotated tokens before anyone can observe them.
      storage.save(refreshed)
      session = refreshed
      return refreshed
    } catch let error as TokenRefreshError {
      if case .authFailure(let detail) = error {
        PHLog.auth.error("refresh terminally failed (\(detail, privacy: .public)); signing out")
        session = nil
        storage.clear()
        events.yield(.sessionInvalidated)
      }
      throw error
    }
  }

  private static func performRefresh(
    current: StoredSession,
    transport: HTTPTransport
  ) async throws -> StoredSession {
    // Refresh must present the client the tokens were issued to.
    guard
      let clientID = current.clientID
        ?? AuthConfiguration.preregisteredClientID(for: current.region)
    else {
      throw TokenRefreshError.authFailure(detail: "no_client_id")
    }
    let configuration = AuthConfiguration(region: current.region, clientID: clientID)
    let request = TokenEndpoint.makeRequest(
      url: configuration.tokenURL,
      fields: [
        ("grant_type", "refresh_token"),
        ("refresh_token", current.refreshToken),
        ("client_id", configuration.clientID),
      ]
    )

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch {
      throw TokenRefreshError.network
    }

    guard (200..<300).contains(response.statusCode) else {
      throw TokenEndpoint.classifyFailure(status: response.statusCode, body: data)
    }

    let token: TokenResponse
    do {
      token = try JSONDecoder().decode(TokenResponse.self, from: data)
    } catch {
      throw TokenRefreshError.unknown(detail: "token_decode_failed")
    }

    var refreshed = current
    refreshed.accessToken = token.accessToken
    refreshed.refreshToken = token.refreshToken
    refreshed.expiresAt = Date.now.addingTimeInterval(token.expiresIn)
    if let teams = token.scopedTeams {
      refreshed.scopedTeams = teams
    }
    return refreshed.resolvingSelectedProject()
  }
}
