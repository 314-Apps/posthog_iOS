import SwiftUI
import UIKit

/// The design language's color tokens, light/dark as one dynamic color.
/// Grounded in the web app's `frontend/src/styles/base.scss`: warm "3000"
/// neutrals (never pure white page background), orange as accent-never-field,
/// blue for chart series and links, purple for anything Max/AI.
public enum PHColor {
  // Surfaces
  public static let background = dynamic(light: 0xEEEF_E9, dark: 0x2124_2B)
  public static let surface = dynamic(light: 0xFFFF_FF, dark: 0x2A2D_35)
  public static let surfaceSecondary = dynamic(light: 0xF7F8_F2, dark: 0x1B1D_24)
  public static let border = dynamic(light: 0xDCDD_D5, dark: 0x3A3D_45)
  public static let divider = dynamic(light: 0xECED_E6, dark: 0x3437_40)

  // Text
  public static let textPrimary = dynamic(light: 0x1D1F_27, dark: 0xEEEF_E9)
  public static let textSecondary = dynamic(light: 0x6B6E_66, dark: 0xB8BA_B1)
  public static let textTertiary = dynamic(light: 0x9B9E_94, dark: 0x7A7D_74)
  public static let textInactive = dynamic(light: 0x8A8D_82, dark: 0x6B6E_66)

  // Brand
  public static let accent = dynamic(light: 0xF54E_00, dark: 0xFF6B_2B)
  public static let link = dynamic(light: 0x1D4A_FF, dark: 0x8FA6_FF)
  public static let highlight = dynamic(light: 0xF7BD_2B, dark: 0xF7BD_2B)
  public static let ai = dynamic(light: 0xA626_D9, dark: 0xC155_F0)

  // Semantics
  public static let success = dynamic(light: 0x1E7B_36, dark: 0x4CC2_6A)
  public static let successFill = dynamic(light: 0x34C7_59, dark: 0x34C7_59)
  public static let danger = dynamic(light: 0xB326_1E, dark: 0xFF6B_5E)
  public static let dangerFill = dynamic(light: 0xD930_25, dark: 0xD930_25)

  /// Categorical chart palette, anchored on brand colors, ordered for contrast.
  public static let series: [Color] = [
    dynamic(light: 0x1D4A_FF, dark: 0x5468_FF),
    dynamic(light: 0xF54E_00, dark: 0xFF6B_2B),
    dynamic(light: 0xF7BD_2B, dark: 0xF7BD_2B),
    dynamic(light: 0x30AB_C6, dark: 0x4FC7_E0),
    dynamic(light: 0xA626_D9, dark: 0xC155_F0),
    dynamic(light: 0x1E7B_36, dark: 0x4CC2_6A),
    dynamic(light: 0xD930_25, dark: 0xFF6B_5E),
    dynamic(light: 0x6B6E_66, dark: 0x9B9E_94),
  ]

  /// The comparison ("previous period") series.
  public static let seriesPrevious = dynamic(light: 0xC6C8_BF, dark: 0x5A5D_66)

  public static func series(at index: Int) -> Color {
    series[index % series.count]
  }

  static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(
      UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
      })
  }
}

extension UIColor {
  convenience init(rgb: UInt32) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1
    )
  }
}
