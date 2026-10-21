import Foundation
import PostHog
import PostHogFoundation

/// Dogfood instrumentation: the app reports its own usage to a PostHog
/// project through the posthog-ios SDK. Dormant until a key is configured
/// (`PostHogDogfoodAPIKey` in Info.plist, injected via xcconfig).
@MainActor
public enum Analytics {
  private static var isEnabled = false

  public static func bootstrap() {
    guard let key = Bundle.main.infoDictionary?["PostHogDogfoodAPIKey"] as? String,
      !key.isEmpty, key.hasPrefix("phc_")
    else {
      PHLog.ui.info("dogfood analytics disabled (no key configured)")
      return
    }
    let config = PostHogConfig(apiKey: key, host: "https://us.i.posthog.com")
    config.captureApplicationLifecycleEvents = true
    config.captureScreenViews = false  // SwiftUI screens are captured manually.
    PostHogSDK.shared.setup(config)
    isEnabled = true
  }

  public static func screen(_ name: String) {
    guard isEnabled else { return }
    PostHogSDK.shared.screen(name)
  }

  public static func capture(_ event: String, properties: [String: Any]? = nil) {
    guard isEnabled else { return }
    PostHogSDK.shared.capture(event, properties: properties)
  }

  public static func reset() {
    guard isEnabled else { return }
    PostHogSDK.shared.reset()
  }
}
