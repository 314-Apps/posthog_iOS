import Foundation
import Testing

@testable import PostHogAPI
@testable import PostHogAuth

@Suite struct AuthFlowTests {
  @Test func authorizeURLCarriesEveryRequiredParameter() throws {
    let configuration = AuthConfiguration(region: .us, clientID: "client-under-test")
    let pkce = PKCEPair()
    let url = configuration.makeAuthorizeURL(pkce: pkce, state: "st4te")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let params = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    )
    #expect(components.host == "us.posthog.com")
    #expect(components.path == "/oauth/authorize/")
    #expect(params["response_type"] == "code")
    #expect(params["code_challenge_method"] == "S256")
    #expect(params["code_challenge"] == pkce.challenge)
    #expect(params["state"] == "st4te")
    #expect(params["redirect_uri"] == "posthog-ios://oauth/callback")
    #expect(params["required_access_level"] == "project")
    #expect(params["scope"]?.contains("query:read") == true)
    #expect(params["scope"]?.contains("feature_flag:write") == true)
  }

  @Test func callbackParsingEnforcesState() throws {
    let good = URL(string: "posthog-ios://oauth/callback?code=abc&state=xyz")!
    #expect(try AuthService.parseCallback(good, expectedState: "xyz") == "abc")

    let badState = URL(string: "posthog-ios://oauth/callback?code=abc&state=evil")!
    #expect(throws: SignInError.self) {
      _ = try AuthService.parseCallback(badState, expectedState: "xyz")
    }

    let noCode = URL(string: "posthog-ios://oauth/callback?state=xyz")!
    #expect(throws: SignInError.self) {
      _ = try AuthService.parseCallback(noCode, expectedState: "xyz")
    }
  }

  @Test func formBodyPercentEncodes() {
    let body = TokenEndpoint.formBody([("a", "x y+z"), ("b", "c&d=e")])
    #expect(String(bytes: body, encoding: .utf8) == "a=x%20y%2Bz&b=c%26d%3De")
  }

  @Test func classifierTable() {
    func classify(_ status: Int, _ body: String) -> TokenRefreshError {
      TokenEndpoint.classifyFailure(status: status, body: Data(body.utf8))
    }
    #expect(classify(401, "") == .authFailure(detail: "http_401"))
    #expect(classify(400, #"{"error":"invalid_grant"}"#) == .authFailure(detail: "invalid_grant"))
    #expect(classify(400, #"{"error":"invalid_client"}"#) == .unknown(detail: "invalid_client"))
    #expect(classify(400, "not json") == .unknown(detail: "http_400"))
    #expect(classify(503, "") == .serverError(status: 503))
  }
}
