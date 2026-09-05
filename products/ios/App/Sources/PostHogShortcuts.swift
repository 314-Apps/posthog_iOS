import AppIntents
import AppShell
import Foundation

/// Siri and Spotlight entry points. Intents record the requested tab and open
/// the app; the shell picks the handoff up on activation (OpenURLIntent needs
/// iOS 18, and the deployment target is 17).
struct AskMaxIntent: AppIntent {
  static let title: LocalizedStringResource = "Ask Max"
  static let description = IntentDescription("Open Max, the PostHog analytics assistant.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    TabHandoff.request(.max)
    return .result()
  }
}

struct OpenPulseIntent: AppIntent {
  static let title: LocalizedStringResource = "Show my metrics"
  static let description = IntentDescription("Open the PostHog project pulse.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    TabHandoff.request(.home)
    return .result()
  }
}

struct PostHogShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AskMaxIntent(),
      phrases: ["Ask Max in \(.applicationName)", "Ask \(.applicationName)"],
      shortTitle: "Ask Max",
      systemImageName: "sparkles"
    )
    AppShortcut(
      intent: OpenPulseIntent(),
      phrases: ["Show my metrics in \(.applicationName)", "Open \(.applicationName) pulse"],
      shortTitle: "Project pulse",
      systemImageName: "chart.xyaxis.line"
    )
  }
}
