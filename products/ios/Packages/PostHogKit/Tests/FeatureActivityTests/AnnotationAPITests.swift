import Foundation
import PostHogAPI
import PostHogTestSupport
import Testing

@Suite struct AnnotationAPITests {
  private func makeClient(transport: StubTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
  }

  @Test func createSendsProjectScopedBody() async throws {
    let created = #"""
      {
        "id": 7,
        "content": "Launched v2",
        "date_marker": "2026-01-01T00:00:00Z",
        "scope": "project",
        "creation_type": "USR",
        "created_at": "2026-01-01T00:00:05Z"
      }
      """#
    let transport = StubTransport(script: [.response(status: 201, body: Data(created.utf8))])
    let client = makeClient(transport: transport)
    let annotation = try await client.createAnnotation(
      projectID: 1,
      content: "Launched v2",
      dateMarker: Date(timeIntervalSince1970: 1_767_225_600)
    )

    #expect(annotation.id == 7)
    #expect(annotation.content == "Launched v2")
    #expect(annotation.scope == "project")
    #expect(annotation.creationType == "USR")
    #expect(annotation.dateMarker == Date(timeIntervalSince1970: 1_767_225_600))

    let request = transport.requests[0]
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://us.posthog.com/api/projects/1/annotations/")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    #expect(body?["content"] as? String == "Launched v2")
    #expect(body?["date_marker"] as? String == "2026-01-01T00:00:00Z")
    #expect(body?["scope"] as? String == "project")
    #expect(body?.count == 3)
  }

  @Test func deleteIsSoftDeletePatch() async throws {
    let transport = StubTransport(script: [.response(status: 200, body: Data("{}".utf8))])
    let client = makeClient(transport: transport)
    try await client.deleteAnnotation(projectID: 1, annotationID: 7)

    let request = transport.requests[0]
    #expect(request.httpMethod == "PATCH")
    #expect(request.url?.absoluteString == "https://us.posthog.com/api/projects/1/annotations/7/")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Bool]
    #expect(body == ["deleted": true])
  }
}
