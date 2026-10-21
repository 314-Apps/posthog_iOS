import PostHogFoundation
import SwiftUI
import WebKit

/// What the player page reports back while it works.
public enum ReplayPlayerEvent: Equatable, Sendable {
  case progress(loaded: Int, total: Int)
  case ready(duration: Double)
  case time(current: Double)
  case ended
  case failed(String)

  /// Decodes one `postMessage` body. Anything unrecognized is ignored rather
  /// than treated as a failure, so a newer page can add messages safely.
  public init?(message: [String: Any]) {
    switch message["type"] as? String {
    case "progress":
      self = .progress(
        loaded: message["loaded"] as? Int ?? 0,
        total: message["total"] as? Int ?? 0
      )
    case "ready":
      self = .ready(duration: message["duration"] as? Double ?? 0)
    case "time":
      self = .time(current: message["current"] as? Double ?? 0)
    case "ended":
      self = .ended
    case "error":
      self = .failed(message["message"] as? String ?? "The recording stopped playing.")
    default:
      return nil
    }
  }
}

/// What the app asks the player page to do.
public enum ReplayPlayerCommand: Equatable, Sendable {
  case play
  case pause
  case seek(milliseconds: Double)
  case speed(Double)

  public var javaScript: String {
    switch self {
    case .play: return "window.posthogPlayer && window.posthogPlayer.play()"
    case .pause: return "window.posthogPlayer && window.posthogPlayer.pause()"
    case .seek(let ms): return "window.posthogPlayer && window.posthogPlayer.seek(\(Int(ms)))"
    case .speed(let rate): return "window.posthogPlayer && window.posthogPlayer.setSpeed(\(rate))"
    }
  }
}

/// Hosts the bundled player page and carries messages both ways.
///
/// The page is loaded from the app bundle over a private scheme and reads its
/// data through the same scheme, so no recording has to be shared publicly to be
/// watched here. The replayed content is a different matter: rrweb rebuilds
/// recorded nodes attribute for attribute, so a recorded image, stylesheet, font
/// or frame would load from whatever host the recording named. The page's own
/// Content-Security-Policy is what refuses those, and `ReplayNetworkBlock` is the
/// second lock, for a page that somehow ships without one.
struct ReplayBundledPlayer: UIViewRepresentable {
  let loader: ReplaySnapshotLoader
  let page: Data
  let chunkCount: Int
  let isMobileRecording: Bool
  /// Raised each time the app wants the page to do something. The coordinator
  /// runs anything new since the last update.
  let command: (id: Int, value: ReplayPlayerCommand)?
  let onEvent: (ReplayPlayerEvent) -> Void

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.allowsInlineMediaPlayback = true
    configuration.setURLSchemeHandler(
      context.coordinator.schemeHandler,
      forURLScheme: ReplayBlockSchemeHandler.scheme
    )
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: Self.configScript(chunkCount: chunkCount, isMobile: isMobileRecording),
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
      )
    )
    configuration.userContentController.add(context.coordinator, name: "posthogPlayer")

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = false
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.isScrollEnabled = false

    // The page is loaded only once it cannot reach the network, because a
    // replayed page pulls images and fonts from the recorded site otherwise.
    let report = onEvent
    Task { @MainActor in
      guard let block = await ReplayNetworkBlock.compile() else {
        report(.failed("This recording can't play safely on this device. Open it on the web."))
        return
      }
      webView.configuration.userContentController.add(block)
      webView.load(URLRequest(url: ReplayBlockSchemeHandler.pageURL))
    }
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    guard let command, command.id != context.coordinator.lastCommandID else { return }
    context.coordinator.lastCommandID = command.id
    webView.evaluateJavaScript(command.value.javaScript)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      schemeHandler: ReplayBlockSchemeHandler(loader: loader, page: page),
      onEvent: onEvent
    )
  }

  static func configScript(chunkCount: Int, isMobile: Bool) -> String {
    """
    window.__posthog_player_config__ = {
      blockCount: \(chunkCount),
      isMobile: \(isMobile),
      playbackSpeed: 1
    };
    """
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler {
    let schemeHandler: ReplayBlockSchemeHandler
    var lastCommandID = -1

    private let onEvent: (ReplayPlayerEvent) -> Void

    init(schemeHandler: ReplayBlockSchemeHandler, onEvent: @escaping (ReplayPlayerEvent) -> Void) {
      self.schemeHandler = schemeHandler
      self.onEvent = onEvent
    }

    func userContentController(
      _ controller: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let body = message.body as? [String: Any],
        let event = ReplayPlayerEvent(message: body)
      else { return }
      onEvent(event)
    }
  }
}
