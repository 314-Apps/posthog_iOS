import AppShell
import Foundation

extension LaunchConfiguration {
  /// Reads UI-test launch arguments. Production launches carry none.
  static var current: LaunchConfiguration {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-UITestScenario"),
      arguments.indices.contains(index + 1)
    else {
      return .production
    }
    return .uiTest(scenario: arguments[index + 1])
  }
}
