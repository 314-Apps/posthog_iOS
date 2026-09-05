import Foundation
import PostHogFoundation
import WebKit

/// Serves the player page and its recording data to the web view over a private
/// scheme.
///
/// Going through a scheme handler rather than a URL keeps the recording inside
/// the app: the page never holds a token and never reaches the network, so
/// playback does not depend on the recording being shared.
@MainActor
final class ReplayBlockSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "posthog-replay"
  static let pageURL = URL(string: "\(scheme)://player/index.html")!

  private let loader: ReplaySnapshotLoader
  private let page: Data
  private var inFlight: [ObjectIdentifier: Task<Void, Never>] = [:]

  init(loader: ReplaySnapshotLoader, page: Data) {
    self.loader = loader
    self.page = page
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    let path = urlSchemeTask.request.url?.path ?? ""

    if path.hasSuffix("/index.html") {
      respond(to: urlSchemeTask, data: page, mimeType: "text/html")
      return
    }

    guard let index = Self.blockIndex(in: path) else {
      fail(urlSchemeTask, status: 404)
      return
    }

    let key = ObjectIdentifier(urlSchemeTask)
    inFlight[key] = Task { [weak self] in
      guard let self else { return }
      do {
        let data = try await loader.chunk(at: index)
        guard !Task.isCancelled else { return }
        respond(to: urlSchemeTask, data: data, mimeType: "application/jsonl")
      } catch {
        guard !Task.isCancelled else { return }
        PHLog.api.error("replay block \(index) failed: \(error)")
        fail(urlSchemeTask, status: 502)
      }
      inFlight[key] = nil
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
    // Answering a stopped task raises an Objective-C exception, which is not
    // catchable in Swift and takes the app down, so the work has to end here.
    let key = ObjectIdentifier(urlSchemeTask)
    inFlight[key]?.cancel()
    inFlight[key] = nil
  }

  nonisolated static func blockIndex(in path: String) -> Int? {
    guard let range = path.range(of: "/__blocks/") else { return nil }
    return Int(path[range.upperBound...])
  }

  private func respond(to task: any WKURLSchemeTask, data: Data, mimeType: String) {
    guard let url = task.request.url else { return }
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": mimeType,
        "Content-Length": String(data.count),
        // A custom scheme gives the page an opaque origin, so its own fetches
        // read as cross-origin without this.
        "Access-Control-Allow-Origin": "*",
      ]
    )!
    task.didReceive(response)
    task.didReceive(data)
    task.didFinish()
  }

  private func fail(_ task: any WKURLSchemeTask, status: Int) {
    guard let url = task.request.url else { return }
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": "0"]
    )!
    task.didReceive(response)
    task.didReceive(Data())
    task.didFinish()
  }
}
