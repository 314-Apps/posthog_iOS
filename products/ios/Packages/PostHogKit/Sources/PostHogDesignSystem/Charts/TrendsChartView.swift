import Charts
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Trends renderer: line, area, or bar over the series' day buckets, with the
/// comparison period as a dashed neutral line. Draws with Swift Charts —
/// no webviews anywhere near a metric.
public struct TrendsChartView: View {
  public enum Style: Sendable {
    case line
    case area
    case bar

    /// Maps the web display enum ("ActionsLineGraph", "ActionsBar", …).
    public init(display: String?) {
      switch display {
      case "ActionsBar", "ActionsBarValue": self = .bar
      case "ActionsAreaGraph": self = .area
      default: self = .line
      }
    }
  }

  private let series: [SeriesResult]
  private let style: Style

  public init(series: [SeriesResult], style: Style = .line) {
    self.series = series
    self.style = style
  }

  private var current: [SeriesResult] { series.filter { !$0.isPrevious } }
  private var previous: [SeriesResult] { series.filter(\.isPrevious) }

  public var body: some View {
    Chart {
      ForEach(Array(previous.enumerated()), id: \.offset) { _, one in
        ForEach(Array(one.data.enumerated()), id: \.offset) { index, value in
          LineMark(
            x: .value("Bucket", index),
            y: .value("Previous", value),
            series: .value("Series", "previous-\(one.label)")
          )
          .foregroundStyle(PHColor.seriesPrevious)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
          .interpolationMethod(.catmullRom)
        }
      }
      ForEach(Array(current.enumerated()), id: \.offset) { seriesIndex, one in
        ForEach(Array(one.data.enumerated()), id: \.offset) { index, value in
          switch style {
          case .line:
            LineMark(
              x: .value("Bucket", index),
              y: .value("Value", value),
              series: .value("Series", one.label + String(seriesIndex))
            )
            .foregroundStyle(PHColor.series(at: seriesIndex))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
          case .area:
            AreaMark(x: .value("Bucket", index), y: .value("Value", value))
              .foregroundStyle(PHColor.series(at: seriesIndex).opacity(0.18))
              .interpolationMethod(.catmullRom)
            LineMark(
              x: .value("Bucket", index),
              y: .value("Value", value),
              series: .value("Series", one.label + String(seriesIndex))
            )
            .foregroundStyle(PHColor.series(at: seriesIndex))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
          case .bar:
            BarMark(x: .value("Bucket", index), y: .value("Value", value))
              .foregroundStyle(PHColor.series(at: seriesIndex))
              .cornerRadius(3)
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(PHColor.divider)
        AxisValueLabel {
          if let index = value.as(Int.self), let label = bucketLabel(at: index) {
            Text(label)
              .font(.caption2)
              .foregroundStyle(PHColor.textTertiary)
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(PHColor.divider)
        AxisValueLabel()
          .font(.caption2)
          .foregroundStyle(PHColor.textTertiary)
      }
    }
    .accessibilityLabel(accessibilitySummary)
  }

  private func bucketLabel(at index: Int) -> String? {
    guard let first = current.first ?? previous.first else { return nil }
    if first.labels.indices.contains(index) { return first.labels[index] }
    if first.days.indices.contains(index) { return first.days[index] }
    return nil
  }

  private var accessibilitySummary: String {
    guard let first = current.first else { return "No data" }
    return "\(first.label), total \(MetricFormat.compact(first.count))"
  }
}
