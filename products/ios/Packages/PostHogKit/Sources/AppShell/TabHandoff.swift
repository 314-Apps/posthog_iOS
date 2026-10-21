import Foundation

/// One-shot tab handoff between App Intents and the shell: an intent records
/// the requested tab, the shell consumes it on activation.
public enum TabHandoff {
  static let key = "handoff.tab"

  public static func request(_ tab: AppTab) {
    UserDefaults.standard.set(tab.rawValue, forKey: key)
  }

  public static func consume() -> AppTab? {
    guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
    UserDefaults.standard.removeObject(forKey: key)
    return AppTab(rawValue: raw)
  }
}
