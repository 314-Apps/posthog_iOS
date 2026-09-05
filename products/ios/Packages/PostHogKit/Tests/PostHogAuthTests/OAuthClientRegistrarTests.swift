import Foundation
import PostHogFoundation
import PostHogTestSupport
import Testing

@testable import PostHogAPI
@testable import PostHogAuth

@Suite struct OAuthClientRegistrarTests {
  private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "registrar-tests-\(UUID().uuidString)")!
  }

  private let registrationBody = Data(
    #"{"client_id":"dcr-issued-id","token_endpoint_auth_method":"none"}"#.utf8
  )

  @Test func knownInstancesUseTheirShippedClientAndNeverRegister() async throws {
    let transport = StubTransport(script: [])
    let registrar = OAuthClientRegistrar(transport: transport, defaults: makeDefaults())
    for region in [Region.us, .eu, .dev] {
      let shipped = try #require(AuthConfiguration.preregisteredClientID(for: region))
      #expect(try await registrar.clientID(for: region) == shipped)
    }
    #expect(transport.callCount == 0)
  }

  @Test func unknownInstanceRegistersOnceThenReusesTheResult() async throws {
    let defaults = makeDefaults()
    let transport = StubTransport(script: [.response(status: 201, body: registrationBody)])
    let registrar = OAuthClientRegistrar(transport: transport, defaults: defaults)
    let region = Region.selfHosted(host: URL(string: "https://posthog.example.com")!)

    #expect(try await registrar.clientID(for: region) == "dcr-issued-id")
    // A second resolve, and a fresh registrar over the same storage, both hit
    // the cache rather than registering again.
    #expect(try await registrar.clientID(for: region) == "dcr-issued-id")
    let reopened = OAuthClientRegistrar(transport: transport, defaults: defaults)
    #expect(try await reopened.clientID(for: region) == "dcr-issued-id")
    #expect(transport.callCount == 1)

    let request = transport.requests[0]
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://posthog.example.com/oauth/register/")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["redirect_uris"]?[0]?.stringValue == "posthog-ios://oauth/callback")
    #expect(body["token_endpoint_auth_method"]?.stringValue == "none")
    // The instance rejects a client_name that starts with "posthog".
    let name = try #require(body["client_name"]?.stringValue)
    #expect(!name.lowercased().hasPrefix("posthog"))
  }

  @Test func refusedRegistrationSurfacesTheInstanceResponse() async {
    let transport = StubTransport(script: [
      .response(status: 400, body: Data(#"{"error":"invalid_redirect_uri"}"#.utf8))
    ])
    let registrar = OAuthClientRegistrar(transport: transport, defaults: makeDefaults())
    let region = Region.selfHosted(host: URL(string: "https://posthog.example.com")!)
    do {
      _ = try await registrar.clientID(for: region)
      Issue.record("expected registration to fail")
    } catch let error as OAuthClientRegistrar.RegistrationError {
      guard case .rejected(let status, let detail) = error else {
        Issue.record("expected .rejected, got \(error)")
        return
      }
      #expect(status == 400)
      #expect(detail?.contains("invalid_redirect_uri") == true)
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func forgettingAClientRegistersAgain() async throws {
    let defaults = makeDefaults()
    let transport = StubTransport(script: [
      .response(status: 201, body: registrationBody),
      .response(status: 201, body: Data(#"{"client_id":"second-id"}"#.utf8)),
    ])
    let registrar = OAuthClientRegistrar(transport: transport, defaults: defaults)
    let region = Region.selfHosted(host: URL(string: "https://posthog.example.com")!)

    #expect(try await registrar.clientID(for: region) == "dcr-issued-id")
    registrar.forget(region: region)
    #expect(try await registrar.clientID(for: region) == "second-id")
    #expect(transport.callCount == 2)
  }
}
