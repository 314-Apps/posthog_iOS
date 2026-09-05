import Foundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI
@testable import PostHogAuth

@Suite struct PersonalAPIKeyTests {
  private func makeKeySession() -> StoredSession {
    StoredSession(
      accessToken: "phx_selfhosted",
      refreshToken: "",
      expiresAt: .distantFuture,
      region: .selfHosted(host: URL(string: "https://posthog.example.com")!),
      scopeVersion: AuthConfiguration.scopeVersion,
      scopedTeams: [],
      authMethod: .personalAPIKey
    )
  }

  @Test func keySessionsNeverRefresh() async throws {
    let transport = StubTransport(script: [])
    let broker = TokenBroker(
      storage: InMemorySessionStore(),
      transport: transport,
      session: makeKeySession()
    )
    let token = try await broker.validAccessToken()
    #expect(token == "phx_selfhosted")
    #expect(transport.callCount == 0)
  }

  @Test func rejectedKeyIsTerminal() async {
    let storage = InMemorySessionStore()
    storage.save(makeKeySession())
    let broker = TokenBroker(
      storage: storage,
      transport: StubTransport(script: []),
      session: makeKeySession()
    )
    do {
      _ = try await broker.refreshedAccessToken()
      Issue.record("expected terminal failure")
    } catch let error as TokenRefreshError {
      guard case .authFailure = error else {
        Issue.record("expected authFailure, got \(error)")
        return
      }
      #expect(storage.load() == nil)
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func oauthBlobWithoutAuthMethodDecodesAsOAuth() throws {
    // A session persisted before self-hosted support has no auth_method key.
    let legacy = #"""
      {"accessToken": "pha_x", "refreshToken": "rt", "expiresAt": 700000000,
       "region": "us", "scopeVersion": 1, "scopedTeams": [1]}
      """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let session = try decoder.decode(StoredSession.self, from: Data(legacy.utf8))
    #expect(session.authMethod == nil)
    #expect(session.isPersonalAPIKey == false)
  }
}
