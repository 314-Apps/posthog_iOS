import Foundation
import PostHogAuth
import SwiftUI

/// The app's composition root, built once at launch. The `SessionStore` it
/// owns is the single source of session truth; features receive a
/// `ProjectContext` by value from the shell.
@MainActor
public struct AppDependencies {
  public let launchConfiguration: LaunchConfiguration
  public let session: SessionStore

  public init(launchConfiguration: LaunchConfiguration, session: SessionStore) {
    self.launchConfiguration = launchConfiguration
    self.session = session
  }

  public static func live(launchConfiguration: LaunchConfiguration) -> AppDependencies {
    let storage: SessionStorage =
      switch launchConfiguration {
      case .production:
        KeychainSessionStore()
      case .uiTest:
        InMemorySessionStore()
      }
    return AppDependencies(
      launchConfiguration: launchConfiguration,
      session: SessionStore(storage: storage)
    )
  }
}

extension View {
  public func appDependencies(_ dependencies: AppDependencies) -> some View {
    environment(dependencies.session)
  }
}
