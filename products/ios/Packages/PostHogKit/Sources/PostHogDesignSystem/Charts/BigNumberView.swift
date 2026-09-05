import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The BoldNumber display: one hero value, optional comparison delta.
public struct BigNumberView: View {
  private let series: [SeriesResult]

  public init(series: [SeriesResult]) {
    self.series = series
  }

  private var currentValue: Double? {
    let current = series.first { !$0.isPrevious }
    return current?.aggregatedValue ?? current?.count
  }

  private var deltaFraction: Double? {
    guard let current = currentValue,
      let previous = series.first(where: \.isPrevious)
        .map({ $0.aggregatedValue ?? $0.count }),
      previous != 0
    else { return nil }
    return (current - previous) / previous
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      if let currentValue {
        Text(MetricFormat.full(currentValue))
          .font(PHFont.metricLarge())
          .phMetricStyle()
          .foregroundStyle(PHColor.textPrimary)
          .contentTransition(.numericText())
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        if let deltaFraction {
          DeltaBadge(fraction: deltaFraction)
        }
      } else {
        Text("–")
          .font(PHFont.metricLarge())
          .foregroundStyle(PHColor.textTertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
