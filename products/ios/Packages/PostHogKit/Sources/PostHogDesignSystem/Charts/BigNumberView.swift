import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The BoldNumber display: one hero value, optional comparison delta.
public struct BigNumberView: View {
  private let series: [SeriesResult]
  private let onSelect: (() -> Void)?

  @State private var selectionCount = 0

  public init(series: [SeriesResult], onSelect: (() -> Void)? = nil) {
    self.series = series
    self.onSelect = onSelect
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
    if let onSelect {
      Button {
        selectionCount += 1
        onSelect()
      } label: {
        value
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(PHPressableStyle())
      .sensoryFeedback(.selection, trigger: selectionCount)
      .accessibilityLabel(accessibilityLabel)
    } else {
      value
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var value: some View {
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
  }

  private var accessibilityLabel: String {
    guard let currentValue else { return "No value yet" }
    let label = series.first { !$0.isPrevious }?.label ?? ""
    let name = label.isEmpty ? "Total" : label
    return "\(name), \(MetricFormat.full(currentValue)). Double tap to see the people."
  }
}
