import SwiftUI

/// The app's root: switches between the signed-out flow and the signed-in shell.
/// Session-phase switching arrives with `SessionStore` in the auth build step.
public struct RootView: View {
  public init() {}

  public var body: some View {
    VStack(spacing: 12) {
      Text("PostHog")
        .font(.system(size: 36, weight: .heavy))
      Text("Scaffold build — sign-in flow lands next.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}
