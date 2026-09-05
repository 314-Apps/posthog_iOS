import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureErrors

@MainActor
@Suite struct ErrorIssueDetailModelTests {
  private func makeModel(transport: StubTransport) -> ErrorIssueDetailModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-errors-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return ErrorIssueDetailModel(context: context, issueID: "issue-1")
  }

  private let activeIssue = Data(
    #"{"id": "issue-1", "name": "TypeError", "status": "active", "first_seen": "2026-08-30T10:00:00Z"}"#
      .utf8
  )

  @Test func resolveFlipsOptimisticallyAndKeepsTheServerResponse() async throws {
    let resolved = Data(#"{"id": "issue-1", "name": "TypeError", "status": "resolved"}"#.utf8)
    let transport = StubTransport(script: [
      .response(status: 200, body: activeIssue),
      .slowResponse(status: 200, body: resolved, delay: 0.2),
    ])
    let model = makeModel(transport: transport)
    await model.loadIssue()
    #expect(model.issue?.status == .active)

    let update = Task { await model.setStatus(.resolved) }
    var attempts = 0
    while !model.isUpdating, attempts < 1000 {
      attempts += 1
      await Task.yield()
    }
    // Mid-flight: the status already shows the target while the PATCH runs.
    #expect(model.issue?.status == .resolved)
    await update.value

    #expect(model.issue?.status == .resolved)
    #expect(model.lastActionSucceeded)
    #expect(model.actionError == nil)
    #expect(!model.isUpdating)

    let patch = transport.requests[1]
    #expect(patch.httpMethod == "PATCH")
    #expect(patch.url?.absoluteString == "https://us.posthog.com/api/projects/1/error_tracking/issues/issue-1/")
    let patchBody = try JSONDecoder().decode(JSONValue.self, from: patch.httpBody ?? Data())
    #expect(patchBody == ["status": "resolved"])
  }

  @Test func failedPatchRevertsTheStatus() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: activeIssue),
      .response(status: 500, body: Data()),
    ])
    let model = makeModel(transport: transport)
    await model.loadIssue()
    await model.setStatus(.suppressed)

    #expect(model.issue?.status == .active)
    #expect(model.actionError != nil)
    #expect(!model.lastActionSucceeded)
    #expect(!model.isUpdating)
  }

  @Test func failedIssueLoadFlagsTheFailure() async {
    let transport = StubTransport(script: [.response(status: 500, body: Data())])
    let model = makeModel(transport: transport)
    await model.loadIssue()
    #expect(model.issue == nil)
    #expect(model.loadFailed)
  }
}
