import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureReplay

@MainActor
@Suite struct ReplayExportModelTests {
  private func makeModel(transport: StubTransport) -> ReplayExportModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-replay-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return ReplayExportModel(
      context: context,
      sessionID: "session-1",
      pollInterval: .milliseconds(1),
      timeout: .seconds(5)
    )
  }

  @Test func exportPollsUntilContentThenDownloadsTheVideo() async throws {
    let videoBytes = Data("mp4-bytes".utf8)
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(#"{"id": 42}"#.utf8)),
      .response(status: 200, body: Data(#"{"id": 42, "has_content": false, "exception": null}"#.utf8)),
      .response(status: 200, body: Data(#"{"id": 42, "has_content": true, "exception": null}"#.utf8)),
      .response(status: 200, body: videoBytes),
    ])
    let model = makeModel(transport: transport)
    await model.export()

    guard case .ready(let fileURL) = model.state else {
      Issue.record("expected .ready, got \(model.state)")
      return
    }
    #expect(try Data(contentsOf: fileURL) == videoBytes)
    #expect(fileURL.pathExtension == "mp4")

    let create = transport.requests[0]
    #expect(create.httpMethod == "POST")
    #expect(create.url?.path() == "/api/projects/1/exports/")
    let body = try JSONDecoder().decode(JSONValue.self, from: create.httpBody ?? Data())
    #expect(body["export_format"] == "video/mp4")
    #expect(body["export_context"]?["session_recording_id"] == "session-1")

    #expect(transport.requests[1].url?.path() == "/api/projects/1/exports/42/")
    #expect(transport.requests[2].url?.path() == "/api/projects/1/exports/42/")
    #expect(transport.requests[3].url?.path() == "/api/projects/1/exports/42/content/")
  }

  @Test func serverSideExceptionFailsTheExport() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Data(#"{"id": 42}"#.utf8)),
      .response(status: 200, body: Data(#"{"id": 42, "has_content": false, "exception": "boom"}"#.utf8)),
    ])
    let model = makeModel(transport: transport)
    await model.export()

    #expect(model.state == .failed("Couldn't render the video. Try again in a moment."))
    #expect(transport.callCount == 2)
  }
}
