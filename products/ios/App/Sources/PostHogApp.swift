import AppShell
import SwiftUI

@main
struct PostHogApp: App {
  @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

  private let dependencies: AppDependencies

  init() {
    self.dependencies = AppDependencies.live(launchConfiguration: LaunchConfiguration.current)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .appDependencies(dependencies)
    }
  }
}
