import Foundation

/// Number and date presentation shared by every metric surface.
/// All formatters are en-US-POSIX-stable where the web app is, and locale-aware elsewhere.
public enum MetricFormat {
  /// Compact count: 950 → "950", 12_847 → "12.8K", 1_310_000 → "1.3M".
  public static func compact(_ value: Double) -> String {
    let magnitude = abs(value)
    let sign = value < 0 ? "-" : ""
    switch magnitude {
    case 1_000_000_000...:
      return sign + trimmed(magnitude / 1_000_000_000) + "B"
    case 1_000_000...:
      return sign + trimmed(magnitude / 1_000_000) + "M"
    case 10_000...:
      return sign + trimmed(magnitude / 1_000) + "K"
    default:
      return value.formatted(.number.precision(.fractionLength(0...1)))
    }
  }

  public static func compact(_ value: Int) -> String {
    compact(Double(value))
  }

  /// Full count with grouping: 12847 → "12,847".
  public static func full(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }

  /// Percent with one decimal at most: 0.124 → "12.4%".
  public static func percent(fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0...1)))
  }

  /// Signed delta for comparison badges: 0.124 → "+12.4%", -0.018 → "−1.8%".
  public static func signedPercent(fraction: Double) -> String {
    let formatted = abs(fraction).formatted(.percent.precision(.fractionLength(0...1)))
    return fraction < 0 ? "−" + formatted : "+" + formatted
  }

  /// Duration in the replay style: 272 → "4:32", 3_725 → "1:02:05".
  public static func duration(seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  private static func trimmed(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}

public enum RelativeDateFormat {
  /// "4 min ago", "2 hours ago", "yesterday" — for list rows and freshness captions.
  public static func ago(_ date: Date, relativeTo now: Date = .now) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
  }
}
