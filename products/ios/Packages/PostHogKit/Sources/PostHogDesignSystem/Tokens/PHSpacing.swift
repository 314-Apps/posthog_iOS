import SwiftUI

/// 4-pt spacing grid and the two corner radii the design language allows.
public enum PHSpacing {
  public static let xs: CGFloat = 4
  public static let sm: CGFloat = 8
  public static let md: CGFloat = 12
  public static let lg: CGFloat = 16
  public static let xl: CGFloat = 24
  public static let xxl: CGFloat = 32
}

public enum PHRadius {
  /// Cards, sheets, tiles.
  public static let card: CGFloat = 16
  /// Buttons, inputs, small containers.
  public static let control: CGFloat = 14
}
