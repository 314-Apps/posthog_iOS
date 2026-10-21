import Foundation

/// How the process was launched. UI tests seed a fake session and a mock server
/// through `.uiTest`; everything else is `.production`.
public enum LaunchConfiguration: Sendable, Equatable {
  case production
  case uiTest(scenario: String)
}
