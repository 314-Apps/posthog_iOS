import Foundation
import SwiftUI

/// The app's composition root: every service the features need, built once at launch.
/// Feature view models receive exactly the protocols they use via initializer injection;
/// this struct only rides the SwiftUI environment down to the screens that construct them.
public struct AppDependencies: Sendable {
  public let launchConfiguration: LaunchConfiguration

  public init(launchConfiguration: LaunchConfiguration) {
    self.launchConfiguration = launchConfiguration
  }

  public static func live(launchConfiguration: LaunchConfiguration) -> AppDependencies {
    AppDependencies(launchConfiguration: launchConfiguration)
  }
}

private struct AppDependenciesKey: EnvironmentKey {
  static let defaultValue: AppDependencies? = nil
}

extension EnvironmentValues {
  public var appDependencies: AppDependencies? {
    get { self[AppDependenciesKey.self] }
    set { self[AppDependenciesKey.self] = newValue }
  }
}

extension View {
  public func appDependencies(_ dependencies: AppDependencies) -> some View {
    environment(\.appDependencies, dependencies)
  }
}
