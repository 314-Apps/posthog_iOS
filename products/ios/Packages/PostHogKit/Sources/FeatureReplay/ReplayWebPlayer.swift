import SwiftUI
import WebKit

/// WKWebView host for the `/embedded/<token>` replay page. The web view is
/// transparent so PHColor.background shows through while the page paints;
/// `isLoading` flips off on didFinish so the caller can drop its skeleton.
struct ReplayWebPlayer: UIViewRepresentable {
  let url: URL
  @Binding var isLoading: Bool

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    // The embed session is throwaway; keep its cookies out of shared storage.
    configuration.websiteDataStore = .nonPersistent()
    configuration.allowsInlineMediaPlayback = true
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = false
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.navigationDelegate = context.coordinator
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    guard context.coordinator.loadedURL != url else { return }
    context.coordinator.loadedURL = url
    webView.load(URLRequest(url: url))
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(isLoading: $isLoading)
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var loadedURL: URL?

    private let isLoading: Binding<Bool>

    init(isLoading: Binding<Bool>) {
      self.isLoading = isLoading
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isLoading.wrappedValue = false
    }

    func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      isLoading.wrappedValue = false
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      isLoading.wrappedValue = false
    }
  }
}
