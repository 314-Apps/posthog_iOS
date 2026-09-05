import SwiftUI

/// The pressed state for tappable chart elements. Chart marks carry their own
/// color, so the press dims the element instead of tinting it.
struct PHPressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.55 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
