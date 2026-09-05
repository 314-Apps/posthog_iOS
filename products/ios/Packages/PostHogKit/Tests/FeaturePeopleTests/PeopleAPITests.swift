import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

@testable import FeaturePeople

@Suite struct PeopleAPITests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  private let personsPage = Data(
    #"""
    {"count": 1, "next": null, "previous": null, "results": [
    {"id": 1, "uuid": "u-1", "distinct_ids": ["d-1"], "properties": {"email": "ana@example.com"}}]}
    """#.utf8
  )

  @Test func personsSendsSearchOnlyWhenNonEmpty() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: personsPage),
      .response(status: 200, body: personsPage),
    ])
    let client = makeClient(transport: transport)

    let searched = try await client.persons(projectID: 1, search: "ana")
    #expect(searched.results.first?.displayName == "ana@example.com")
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/persons/?search=ana")

    _ = try await client.persons(projectID: 1)
    #expect(
      transport.requests[1].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/persons/")
  }

  @Test func decodesCohortsDefensively() async throws {
    let page = #"""
      {"count": 2, "next": null, "previous": null, "results": [
      {"id": 7, "name": "Power users", "count": 12847, "is_static": true,
      "created_at": "2026-08-01T00:00:00Z"},
      {"id": 8}]}
      """#
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(page.utf8))
    ])
    let client = makeClient(transport: transport)

    let cohorts = try await client.cohorts(projectID: 1)
    #expect(
      transport.requests[0].url?.absoluteString
        == "https://us.posthog.com/api/projects/1/cohorts/")
    #expect(cohorts.results.count == 2)

    let full = cohorts.results[0]
    #expect(full.id == 7)
    #expect(full.name == "Power users")
    #expect(full.count == 12847)
    #expect(full.isStatic)
    #expect(full.createdAt != nil)

    let sparse = cohorts.results[1]
    #expect(sparse.id == 8)
    #expect(sparse.name == "")
    #expect(sparse.count == nil)
    #expect(!sparse.isStatic)
    #expect(sparse.createdAt == nil)
  }
}
