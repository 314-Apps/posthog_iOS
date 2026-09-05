import Foundation
import Testing

@testable import PostHogAPI

@Suite struct RegionTests {
  @Test func legacyPlainStringsDecode() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Region.self, from: Data("\"us\"".utf8)) == .us)
    #expect(try decoder.decode(Region.self, from: Data("\"eu\"".utf8)) == .eu)
    #expect(try decoder.decode(Region.self, from: Data("\"dev\"".utf8)) == .dev)
  }

  @Test func selfHostedRoundTrips() throws {
    let region = Region.selfHosted(host: URL(string: "https://posthog.example.com")!)
    let data = try JSONEncoder().encode(region)
    let decoded = try JSONDecoder().decode(Region.self, from: data)
    #expect(decoded == region)
    #expect(decoded.apiBaseURL.absoluteString == "https://posthog.example.com")
    #expect(decoded.livestreamBaseURL == nil)
    #expect(decoded.storageKey == "custom-posthog.example.com")
  }

  @Test func cloudRegionsRoundTripUnchanged() throws {
    for region in [Region.us, .eu, .dev] {
      let data = try JSONEncoder().encode(region)
      #expect(try JSONDecoder().decode(Region.self, from: data) == region)
    }
  }

  @Test func unknownRegionFailsLoudly() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(Region.self, from: Data("\"mars\"".utf8))
    }
  }
}
