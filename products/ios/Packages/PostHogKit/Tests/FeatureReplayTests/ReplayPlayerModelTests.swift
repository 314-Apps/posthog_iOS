import Foundation
import PostHogAPI
import PostHogFoundation
import PostHogQueries
import PostHogTestSupport
import Testing

@testable import FeatureReplay

@MainActor
@Suite struct ReplayPlayerModelTests {
  private func makeModel(transport: StubTransport) -> ReplayPlayerModel {
    let client = APIClient(
      baseURL: URL(string: "https://us.posthog.com")!,
      transport: transport,
      tokens: StubTokens(),
      clientInfo: ClientInfo(appVersion: "1.0.0", buildNumber: "1")
    )
    let cacheRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("feature-replay-tests-\(UUID().uuidString)", isDirectory: true)
    let context = ProjectContext(region: .us, projectID: 1, client: client, cache: DiskCache(root: cacheRoot))
    return ReplayPlayerModel(context: context, sessionID: "session-1")
  }

  @Test func enabledSharingBuildsTheEmbedURL() async {
    let sharing = Data(#"{"enabled": true, "access_token": "tok123"}"#.utf8)
    let transport = StubTransport(script: [.response(status: 200, body: sharing)])
    let model = makeModel(transport: transport)
    await model.load()

    let expected = URL(string: "https://us.posthog.com/embedded/tok123?whitelabel&noHeader")!
    #expect(model.state == .ready(expected))
    #expect(transport.callCount == 1)
    #expect(transport.requests[0].httpMethod == "GET")
  }

  /// An enabled share serves the recording to anyone holding the link, with no
  /// login. Opening a recording must never create one, so an unshared recording
  /// reports itself unplayable and the app sends exactly one read.
  @Test func anUnsharedRecordingIsNeverPublishedToPlayIt() async {
    let disabled = Data(#"{"enabled": false, "access_token": null}"#.utf8)
    let transport = StubTransport(script: [.response(status: 200, body: disabled)])
    let model = makeModel(transport: transport)
    await model.load()

    #expect(model.state == .unavailable)
    #expect(transport.callCount == 1)
    #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })
  }

  @Test(arguments: zip([403, 500], [ReplayPlayerModel.State.unavailable, .failed]))
  func sharingErrorMapsToTheHonestState(status: Int, expected: ReplayPlayerModel.State) async {
    let transport = StubTransport(script: [.response(status: status, body: Data())])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.state == expected)
  }
}
