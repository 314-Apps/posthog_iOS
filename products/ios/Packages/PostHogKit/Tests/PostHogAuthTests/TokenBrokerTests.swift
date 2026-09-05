import Foundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI
@testable import PostHogAuth

@Suite struct TokenBrokerTests {
  @Test func freshTokenSkipsRefresh() async throws {
    let transport = StubTransport(script: [])
    let broker = TokenBroker(
      storage: InMemorySessionStore(),
      transport: transport,
      session: makeSession(expiresIn: 3600)
    )
    let token = try await broker.validAccessToken()
    #expect(token == "pha_old")
    #expect(transport.callCount == 0)
  }

  @Test func nearExpiryTriggersRefreshAndPersistsRotation() async throws {
    let storage = InMemorySessionStore()
    let transport = StubTransport(script: [.response(status: 200, body: freshTokenBody)])
    let broker = TokenBroker(
      storage: storage,
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    let token = try await broker.validAccessToken()
    #expect(token == "pha_new")
    let persisted = storage.load()
    #expect(persisted?.accessToken == "pha_new")
    #expect(persisted?.refreshToken == "rt_new")
  }

  @Test func concurrentCallersShareOneRefresh() async throws {
    let transport = StubTransport(script: [
      .slowResponse(status: 200, body: freshTokenBody, delay: 0.2)
    ])
    let broker = TokenBroker(
      storage: InMemorySessionStore(),
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    let tokens = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<8 {
        group.addTask { try await broker.validAccessToken() }
      }
      var collected: [String] = []
      for try await token in group {
        collected.append(token)
      }
      return collected
    }
    #expect(tokens.count == 8)
    #expect(Set(tokens) == ["pha_new"])
    #expect(transport.callCount == 1)
  }

  @Test(arguments: [
    (401, "", true),
    (403, "", true),
    (400, #"{"error":"invalid_grant"}"#, true),
    (400, #"{"error":"invalid_token"}"#, true),
    (400, #"{"error":"invalid_client"}"#, false),
    (500, "", false),
  ])
  func refreshFailureTaxonomy(status: Int, body: String, signsOut: Bool) async {
    let storage = InMemorySessionStore()
    let transport = StubTransport(script: [.response(status: status, body: Data(body.utf8))])
    let broker = TokenBroker(
      storage: storage,
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    storage.save(makeSession(expiresIn: 60))

    do {
      _ = try await broker.validAccessToken()
      Issue.record("expected refresh failure")
    } catch let error as TokenRefreshError {
      if signsOut {
        guard case .authFailure = error else {
          Issue.record("expected authFailure for \(status) \(body), got \(error)")
          return
        }
        #expect(storage.load() == nil)
        let session = await broker.currentSession
        #expect(session == nil)
      } else {
        if case .authFailure = error {
          Issue.record("must not sign out for \(status) \(body)")
        }
        #expect(storage.load() != nil)
        let session = await broker.currentSession
        #expect(session != nil)
      }
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func networkFailureKeepsSession() async {
    let storage = InMemorySessionStore()
    storage.save(makeSession(expiresIn: 60))
    let transport = StubTransport(script: [.error(URLError(.notConnectedToInternet))])
    let broker = TokenBroker(
      storage: storage,
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    do {
      _ = try await broker.validAccessToken()
      Issue.record("expected network failure")
    } catch let error as TokenRefreshError {
      #expect(error == .network)
      #expect(storage.load() != nil)
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func terminalFailureEmitsSessionInvalidated() async throws {
    let transport = StubTransport(script: [
      .response(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
    ])
    let broker = TokenBroker(
      storage: InMemorySessionStore(),
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    _ = try? await broker.validAccessToken()
    var iterator = broker.authEvents.makeAsyncIterator()
    let event = await iterator.next()
    #expect(event == .sessionInvalidated)
  }

  @Test func refreshAfterFailureRetriesFresh() async throws {
    // A serverError (non-terminal) refresh failure must not wedge the broker.
    let transport = StubTransport(script: [
      .response(status: 500, body: Data()),
      .response(status: 200, body: freshTokenBody),
    ])
    let broker = TokenBroker(
      storage: InMemorySessionStore(),
      transport: transport,
      session: makeSession(expiresIn: 60)
    )
    _ = try? await broker.validAccessToken()
    let token = try await broker.validAccessToken()
    #expect(token == "pha_new")
    #expect(transport.callCount == 2)
  }

  @Test func selectedProjectFallsBackWhenDescoped() {
    let session = makeSession(expiresIn: 3600, scopedTeams: [5, 6], selectedProjectID: 99)
    #expect(session.resolvingSelectedProject().selectedProjectID == 5)

    let kept = makeSession(expiresIn: 3600, scopedTeams: [5, 6], selectedProjectID: 6)
    #expect(kept.resolvingSelectedProject().selectedProjectID == 6)

    let orgWide = makeSession(expiresIn: 3600, scopedTeams: [], selectedProjectID: 42)
    #expect(orgWide.resolvingSelectedProject().selectedProjectID == 42)
  }
}
