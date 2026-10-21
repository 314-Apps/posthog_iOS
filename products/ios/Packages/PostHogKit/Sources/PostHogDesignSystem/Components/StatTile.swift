import PostHogFoundation
import SwiftUI

/// A labeled metric: compact number, optional delta, optional caption.
public struct StatTile: View {
  private let label: String
  private let value: String
  private let deltaFraction: Double?
  private let isIncreaseBad: Bool
  private let caption: String?

  public init(
    label: String,
    value: String,
    deltaFraction: Double? = nil,
    isIncreaseBad: Bool = false,
    caption: String? = nil
  ) {
    self.label = label
    self.value = value
    self.deltaFraction = deltaFraction
    self.isIncreaseBad = isIncreaseBad
    self.caption = caption
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: PHSpacing.xs) {
      Text(value)
        .font(PHFont.metricMedium())
        .phMetricStyle()
        .foregroundStyle(PHColor.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      HStack(spacing: PHSpacing.sm) {
        Text(label)
          .font(.caption)
          .foregroundStyle(PHColor.textSecondary)
        if let deltaFraction {
          DeltaBadge(fraction: deltaFraction, isIncreaseBad: isIncreaseBad)
        }
      }
      if let caption {
        Text(caption)
          .font(.caption2)
          .foregroundStyle(PHColor.textTertiary)
      }
    }
  }
}
