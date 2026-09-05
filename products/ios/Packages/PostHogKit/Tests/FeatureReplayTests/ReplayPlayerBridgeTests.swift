import Foundation
import Testing

@testable import FeatureReplay

/// The page and the app agree on these exact strings. A rename on either side
/// makes playback silently do nothing, which no other test would catch.
@Suite struct ReplayPlayerBridgeTests {
  @Test func decodesEveryMessageThePageSends() {
    #expect(
      ReplayPlayerEvent(message: ["type": "progress", "loaded": 2, "total": 5])
        == .progress(loaded: 2, total: 5)
    )
    #expect(ReplayPlayerEvent(message: ["type": "ready", "duration": 42_000.0]) == .ready(duration: 42_000))
    #expect(ReplayPlayerEvent(message: ["type": "time", "current": 1_250.0]) == .time(current: 1_250))
    #expect(ReplayPlayerEvent(message: ["type": "ended"]) == .ended)
    #expect(ReplayPlayerEvent(message: ["type": "error", "message": "boom"]) == .failed("boom"))
  }

  @Test func anUnknownMessageIsIgnoredRatherThanTreatedAsFailure() {
    #expect(ReplayPlayerEvent(message: ["type": "gibberish"]) == nil)
    #expect(ReplayPlayerEvent(message: ["loaded": 1]) == nil)
    #expect(ReplayPlayerEvent(message: [:]) == nil)
  }

  @Test func anErrorWithNoMessageStillSaysSomethingUseful() {
    guard case .failed(let text) = ReplayPlayerEvent(message: ["type": "error"]) else {
      Issue.record("expected a failure")
      return
    }
    #expect(!text.isEmpty)
  }

  @Test func commandsCallTheMethodsThePageDefines() {
    #expect(ReplayPlayerCommand.play.javaScript.contains("posthogPlayer.play()"))
    #expect(ReplayPlayerCommand.pause.javaScript.contains("posthogPlayer.pause()"))
    #expect(ReplayPlayerCommand.seek(milliseconds: 1_500).javaScript.contains("posthogPlayer.seek(1500)"))
    #expect(ReplayPlayerCommand.speed(2).javaScript.contains("posthogPlayer.setSpeed(2.0)"))
  }

  /// Every command guards on the global, so one sent before the page is ready
  /// is a no-op rather than a thrown JavaScript error.
  @Test(
    arguments: [
      ReplayPlayerCommand.play, .pause, .seek(milliseconds: 0), .speed(1),
    ]
  )
  func aCommandSentTooEarlyDoesNothing(_ command: ReplayPlayerCommand) {
    #expect(command.javaScript.hasPrefix("window.posthogPlayer &&"))
  }

  @Test func theConfigNamesWhatThePageReads() {
    let script = ReplayBundledPlayer.configScript(chunkCount: 3, isMobile: true)
    #expect(script.contains("window.__posthog_player_config__"))
    #expect(script.contains("blockCount: 3"))
    #expect(script.contains("isMobile: true"))
  }

  @Test(
    arguments: zip(["/player/__blocks/0", "/player/__blocks/12", "/player/index.html", "/nope"], [0, 12, nil, nil]))
  func blockIndexIsReadFromThePath(_ path: String, _ expected: Int?) {
    #expect(ReplayBlockSchemeHandler.blockIndex(in: path) == expected)
  }
}
