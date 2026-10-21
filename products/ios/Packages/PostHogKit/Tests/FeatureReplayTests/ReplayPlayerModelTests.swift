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

  private static let recording = Data(
    #"{"id": "session-1", "snapshot_source": "web", "viewed": false}"#.utf8
  )
  private static let mobileRecording = Data(
    #"{"id": "session-1", "snapshot_source": "mobile", "viewed": false}"#.utf8
  )
  private static let sources = Data(
    #"""
    {"sources": [
      {"source": "blob_v2", "blob_key": "0", "start_timestamp": "2026-03-14T09:00:00Z"},
      {"source": "blob_v2", "blob_key": "1", "start_timestamp": "2026-03-14T09:01:00Z"}]}
    """#.utf8
  )

  /// The whole point of the change: playback is planned from the authenticated
  /// snapshots API, and nothing reads or writes a share along the way.
  @Test func readyPlansFromSnapshotsAndNeverTouchesSharing() async throws {
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.recording),
      .response(status: 200, body: Self.sources),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    #expect(model.state == .ready(chunkCount: 1, isMobile: false))
    #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(transport.requests.allSatisfy { !($0.url?.path().contains("/sharing") ?? false) })
    let snapshotCall = try #require(transport.requests.last?.url?.path())
    #expect(snapshotCall == "/api/projects/1/session_recordings/session-1/snapshots/")
  }

  /// A mobile recording holds wireframes, so the page has to be told to convert
  /// them or it draws an empty screen.
  @Test func aMobileRecordingIsFlaggedForThePlayer() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.mobileRecording),
      .response(status: 200, body: Self.sources),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    #expect(model.state == .ready(chunkCount: 1, isMobile: true))
  }

  @Test(
    arguments: zip(
      [403, 404, 410, 503],
      [
        ReplayPlayerModel.State.unavailable(.noAccess), .unavailable(.noData),
        .unavailable(.deleted), .unavailable(.tooBusy),
      ]
    )
  )
  func aRefusedRecordingSaysWhichKindOfRefusal(_ status: Int, _ expected: ReplayPlayerModel.State) async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.recording),
      .response(status: status, body: Data()),
    ])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.state == expected)
  }

  /// A recording the API knows about but has no blocks for must not sit on a
  /// spinner forever.
  @Test func aRecordingWithNoBlocksReportsItHasNothingToPlay() async {
    let empty = Data(#"{"sources": []}"#.utf8)
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.recording),
      .response(status: 200, body: empty),
    ])
    let model = makeModel(transport: transport)
    await model.load()
    #expect(model.state == .unavailable(.noData))
  }

  @Test func everyUnavailableReasonTellsThePersonWhatToDo() {
    for reason in [
      ReplayPlayerModel.Unavailable.noAccess, .noData, .deleted, .tooBusy,
    ] {
      #expect(!reason.message.isEmpty)
      #expect(!reason.message.contains("—"))
    }
  }

  /// Each command has to reach the page exactly once, so the raised id must
  /// change on every send.
  @Test func eachCommandIsRaisedOnce() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.recording),
      .response(status: 200, body: Self.sources),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    model.handle(.ready(duration: 5_000))
    let afterReady = model.command?.id
    #expect(model.isPlaying)

    model.pause()
    #expect(model.command?.id != afterReady)
    #expect(model.command?.value == .pause)
    #expect(!model.isPlaying)

    model.seek(to: 1_200)
    #expect(model.command?.value == .seek(milliseconds: 1_200))
    #expect(model.position == 1_200)
  }

  @Test func progressAndEndAreReflected() async {
    let transport = StubTransport(script: [
      .response(status: 200, body: Self.recording),
      .response(status: 200, body: Self.sources),
    ])
    let model = makeModel(transport: transport)
    await model.load()

    model.handle(.progress(loaded: 1, total: 3))
    #expect(model.loadedChunks == 1)
    #expect(model.totalChunks == 3)

    model.handle(.ready(duration: 9_000))
    model.handle(.time(current: 4_000))
    #expect(model.position == 4_000)

    model.handle(.ended)
    #expect(!model.isPlaying)
    #expect(model.position == 9_000)
  }
}
