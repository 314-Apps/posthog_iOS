import SwiftUI

/// Type tokens. SF throughout; display numerics use SF Rounded heavy with
/// monospaced digits — the rounded warmth echoes the hedgehog without a
/// custom typeface. Everything maps through Dynamic Type.
public enum PHFont {
  /// Hero metric (Home pulse, big-number tiles).
  public static func metricLarge() -> Font {
    .system(size: 40, weight: .heavy, design: .rounded)
  }

  public static func metricMedium() -> Font {
    .system(size: 28, weight: .heavy, design: .rounded)
  }

  public static func metricSmall() -> Font {
    .system(size: 20, weight: .bold, design: .rounded)
  }

  /// Flag keys, SQL, stack frames.
  public static func mono(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

extension View {
  /// Every metric value renders with tabular digits so columns never wobble.
  public func phMetricStyle() -> some View {
    monospacedDigit()
  }
}
