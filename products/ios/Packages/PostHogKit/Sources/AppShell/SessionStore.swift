import Foundation
import Observation
import PostHogAPI
import PostHogAuth
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The single owner of auth + project state. Everything user-visible flows
/// from `phase`; features re-fetch via `.task(id: context.projectID)`.
@MainActor
@Observable
public final class SessionStore {
  public enum Phase {
    case loading
    case signedOut
    /// Signed in but no project selected yet (fresh org-wide sign-in).
    case needsProject(StoredSession)
    case signedIn(ProjectContext)
  }

  public private(set) var phase: Phase = .loading
  public private(set) var isSigningIn = false
  public var signInError: String?

  /// Token authority for surfaces that stream outside APIClient (Max's SSE).
  public var tokenProvider: TokenProviding { broker }

  /// Projects the switcher offers, hydrated lazily from the API.
  public private(set) var availableProjects: [Project] = []
  public private(set) var user: User?

  private let broker: TokenBroker
  private let authService: AuthService
  private let cache: DiskCache
  private let transport: HTTPTransport
  private var eventsTask: Task<Void, Never>?

  public init(
    storage: SessionStorage,
    authService: AuthService? = nil,
    cache: DiskCache = DiskCache(),
    transport: HTTPTransport = URLSessionTransport()
  ) {
    self.broker = TokenBroker(storage: storage, transport: transport)
    self.authService = authService ?? AuthService()
    self.cache = cache
    self.transport = transport
    self.eventsTask = Task { [weak self, broker] in
      for await event in broker.authEvents where event == .sessionInvalidated {
        self?.handleInvalidatedSession()
      }
    }
  }

  // MARK: Lifecycle

  public func bootstrap() async {
    guard let session = await broker.currentSession else {
      phase = .signedOut
      return
    }
    // A stored session with an older scope set silently re-authorizes.
    guard session.scopeVersion == AuthConfiguration.scopeVersion else {
      await broker.clear()
      phase = .signedOut
      return
    }
    adopt(session)
  }

  public func signIn(region: Region) async {
    guard !isSigningIn else { return }
    isSigningIn = true
    signInError = nil
    defer { isSigningIn = false }
    do {
      let session = try await authService.signIn(region: region)
      await broker.adopt(session)
      adopt(session)
    } catch SignInError.cancelled {
      // The user closed the sheet; nothing to report.
    } catch SignInError.clientUnavailable {
      signInError =
        "Couldn't reach this instance to start sign-in. "
        + "Check your connection, or sign in with an API key instead."
    } catch {
      PHLog.auth.error("sign-in failed: \(error)")
      signInError = "Couldn't sign in. Check the region and try again."
    }
  }

  /// Self-hosted sign-in: validate the personal API key against the instance,
  /// then persist a non-expiring key-backed session.
  public func signInSelfHosted(host: URL, apiKey: String) async {
    guard !isSigningIn else { return }
    isSigningIn = true
    signInError = nil
    defer { isSigningIn = false }

    struct StaticKey: TokenProviding {
      let key: String
      func validAccessToken() async throws -> String { key }
      func refreshedAccessToken() async throws -> String {
        throw TokenRefreshError.authFailure(detail: "personal_api_key_rejected")
      }
    }

    let probe = APIClient(baseURL: host, transport: transport, tokens: StaticKey(key: apiKey))
    do {
      let me = try await probe.me()
      let session = StoredSession(
        accessToken: apiKey,
        refreshToken: "",
        expiresAt: .distantFuture,
        region: .forHost(host),
        scopeVersion: AuthConfiguration.scopeVersion,
        scopedTeams: [],
        selectedProjectID: me.currentTeamID,
        authMethod: .personalAPIKey
      )
      await broker.adopt(session)
      adopt(session)
    } catch {
      PHLog.auth.error("self-hosted sign-in failed: \(error)")
      signInError = "Couldn't connect. Check the instance URL and API key, then try again."
    }
  }

  public func signOut() async {
    PushRegistrar.shared.unregister()
    PushRegistrar.shared.configure(client: nil)
    if let session = await broker.currentSession {
      await authService.revoke(session: session)
    }
    await broker.clear()
    await cache.removeAll()
    WidgetSnapshotStore.clear()
    availableProjects = []
    user = nil
    phase = .signedOut
  }

  // MARK: Projects

  public func selectProject(_ projectID: Int) async {
    guard var session = await broker.currentSession else { return }
    session.selectedProjectID = projectID
    await broker.adopt(session)
    adopt(session)
  }

  /// Loads the user + project list for the switcher (and the first-run picker).
  public func loadProjects() async {
    guard let session = await broker.currentSession else { return }
    let client = makeClient(region: session.region)
    do {
      let me = try await client.me()
      user = me
      // The current organization's projects ride along on `@me`, which a
      // project-scoped key may call. The organization-nested list rejects such
      // a key outright, so one unreachable organization must not empty the
      // whole switcher.
      var projects = me.currentOrganizationProjects
      for organization in me.organizations where organization.id != me.currentOrganizationID {
        do {
          let page = try await client.organizationProjects(organizationID: organization.id)
          projects.append(contentsOf: page.results)
        } catch {
          PHLog.api.error("projects unavailable for one organization: \(error)")
        }
      }
      // Token-scoped teams are the authority when the grant is project-scoped.
      if !session.scopedTeams.isEmpty {
        projects = projects.filter { session.scopedTeams.contains($0.id) }
      }
      availableProjects = projects
    } catch {
      PHLog.api.error("project list load failed: \(error)")
    }
  }

  // MARK: Internals

  private func adopt(_ session: StoredSession) {
    let resolved = session.resolvingSelectedProject()
    if let projectID = resolved.selectedProjectID {
      let context = makeContext(session: resolved, projectID: projectID)
      PushRegistrar.shared.configure(client: context.client)
      phase = .signedIn(context)
    } else {
      phase = .needsProject(resolved)
    }
  }

  private func makeContext(session: StoredSession, projectID: Int) -> ProjectContext {
    ProjectContext(
      region: session.region,
      projectID: projectID,
      client: makeClient(region: session.region),
      cache: cache
    )
  }

  private func makeClient(region: Region) -> APIClient {
    APIClient(baseURL: region.apiBaseURL, transport: transport, tokens: broker)
  }

  private func handleInvalidatedSession() {
    availableProjects = []
    user = nil
    phase = .signedOut
  }
}
