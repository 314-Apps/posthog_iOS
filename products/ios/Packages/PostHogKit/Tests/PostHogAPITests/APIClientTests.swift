import Foundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI

private struct Widget: Codable, Sendable, Equatable {
  let name: String
}

@Suite struct APIClientTests {
  private let baseURL = URL(string: "https://us.posthog.com")!

  private func makeClient(transport: StubTransport, tokens: StubTokens = StubTokens()) -> APIClient {
    APIClient(
      baseURL: baseURL,
      transport: transport,
      tokens: tokens,
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "42")
    )
  }

  @Test func sendsBearerAndClientHeaders() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(#"{"name":"a"}"#.utf8))
    ])
    let client = makeClient(transport: transport)
    let widget: Widget = try await client.send(.get("/api/projects/1/widgets/"))
    #expect(widget == Widget(name: "a"))
    let request = transport.requests[0]
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pha_valid")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "PostHogiOS/1.0.0 (build 42)")
    #expect(request.value(forHTTPHeaderField: "x-posthog-client") == "posthog-ios-app/1.0.0")
  }

  @Test func retriesOnceWithFreshTokenAfter401() async throws {
    let tokens = StubTokens()
    let transport = StubTransport(script: [
      .response(status: 401, body: Data()),
      .response(status: 200, body: Data(#"{"name":"b"}"#.utf8)),
    ])
    let client = makeClient(transport: transport, tokens: tokens)
    let widget: Widget = try await client.send(.get("/api/projects/1/widgets/"))
    #expect(widget == Widget(name: "b"))
    #expect(tokens.refreshCalls == 1)
    #expect(transport.requests.count == 2)
    #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer pha_refreshed")
  }

  @Test func secondConsecutive401IsUnauthorized() async {
    let transport = StubTransport(script: [
      .response(status: 401, body: Data()),
      .response(status: 401, body: Data()),
    ])
    let client = makeClient(transport: transport)
    await #expect(throws: APIError.self) {
      let _: Widget = try await client.send(.get("/api/projects/1/widgets/"))
    }
  }

  @Test func terminalRefreshFailureIsUnauthorized() async {
    let tokens = StubTokens()
    tokens.validResult = .failure(.authFailure(detail: "invalid_grant"))
    let transport = StubTransport(script: [])
    let client = makeClient(transport: transport, tokens: tokens)
    do {
      let _: Widget = try await client.send(.get("/api/projects/1/widgets/"))
      Issue.record("expected unauthorized")
    } catch let error as APIError {
      guard case .unauthorized = error else {
        Issue.record("expected unauthorized, got \(error)")
        return
      }
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func permission403KeepsSession() async {
    let body = Data(#"{"type":"authentication_error","code":"permission_denied","detail":"nope"}"#.utf8)
    let transport = StubTransport(script: [.response(status: 403, body: body)])
    let client = makeClient(transport: transport)
    do {
      let _: Widget = try await client.send(.get("/api/projects/1/widgets/"))
      Issue.record("expected server error")
    } catch let error as APIError {
      guard case .server(let status, let code, _, _) = error else {
        Issue.record("expected .server, got \(error)")
        return
      }
      #expect(status == 403)
      #expect(code == "permission_denied")
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func honorsRetryAfterOnceOn429() async throws {
    let transport = StubTransport(script: [
      .response(status: 429, body: Data(), headers: ["Retry-After": "0"]),
      .response(status: 200, body: Data(#"{"name":"c"}"#.utf8)),
    ])
    let client = makeClient(transport: transport)
    let widget: Widget = try await client.send(.get("/api/projects/1/widgets/"))
    #expect(widget == Widget(name: "c"))
    #expect(transport.requests.count == 2)
  }

  @Test func retriesTransientNetworkErrorOnGetOnly() async throws {
    let transport = StubTransport(script: [
      .error(URLError(.networkConnectionLost)),
      .response(status: 200, body: Data(#"{"name":"d"}"#.utf8)),
    ])
    let client = makeClient(transport: transport)
    let widget: Widget = try await client.send(.get("/api/projects/1/widgets/"))
    #expect(widget == Widget(name: "d"))

    let postTransport = StubTransport(script: [.error(URLError(.networkConnectionLost))])
    let postClient = makeClient(transport: postTransport)
    await #expect(throws: APIError.self) {
      let _: Widget = try await postClient.send(.post("/api/projects/1/widgets/", body: Data("{}".utf8)))
    }
  }

  @Test func parsesDRFErrorBody() async {
    let body = Data(
      #"{"type":"validation_error","code":"invalid_input","detail":"Bad filter","attr":"date_from"}"#.utf8
    )
    let transport = StubTransport(script: [.response(status: 400, body: body)])
    let client = makeClient(transport: transport)
    do {
      let _: Widget = try await client.send(.get("/api/projects/1/widgets/"))
      Issue.record("expected server error")
    } catch let error as APIError {
      guard case .server(let status, let code, let detail, let attr) = error else {
        Issue.record("expected .server, got \(error)")
        return
      }
      #expect(status == 400)
      #expect(code == "invalid_input")
      #expect(detail == "Bad filter")
      #expect(attr == "date_from")
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func decodesBothISO8601Variants() throws {
    struct Stamped: Decodable {
      let at: Date
    }
    let decoder = APIClient.makeDecoder()
    let fractional = try decoder.decode(Stamped.self, from: Data(#"{"at":"2026-03-14T09:26:53.589Z"}"#.utf8))
    let plain = try decoder.decode(Stamped.self, from: Data(#"{"at":"2026-03-14T09:26:53Z"}"#.utf8))
    #expect(abs(fractional.at.timeIntervalSince(plain.at) - 0.589) < 0.001)
  }
}
