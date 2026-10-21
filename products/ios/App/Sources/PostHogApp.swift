import AppShell
import SwiftUI

@main
struct PostHogApp: App {
  @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

  private let dependencies: AppDependencies

  init() {
    let launch = LaunchConfiguration.current
    self.dependencies = AppDependencies.live(launchConfiguration: launch)
    if launch == .production {
      Analytics.bootstrap()
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .appDependencies(dependencies)
    }
  }
}
