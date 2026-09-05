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

  /// The bucket a finger is on, and the series the emphasized dot sits on.
  struct Selection: Equatable {
    let bucket: Int
    let series: Int
  }

  private let series: [SeriesResult]
  private let style: Style
  private let showsAxes: Bool
  private let onSelectPoint: ((Int, Int) -> Void)?

  @State private var selection: Selection?

  public init(
    series: [SeriesResult],
    style: Style = .line,
    showsAxes: Bool = true,
    onSelectPoint: ((_ bucketIndex: Int, _ seriesIndex: Int) -> Void)? = nil
  ) {
    self.init(
      series: series,
      style: style,
      showsAxes: showsAxes,
      initialSelection: nil,
      onSelectPoint: onSelectPoint
    )
  }

  /// Seeds the selection so a snapshot can capture the indicator, which no
  /// gesture can produce inside a headless render.
  init(
    series: [SeriesResult],
    style: Style,
    showsAxes: Bool,
    initialSelection: Selection?,
    onSelectPoint: ((Int, Int) -> Void)?
  ) {
    self.series = series
    self.style = style
    self.showsAxes = showsAxes
    self.onSelectPoint = onSelectPoint
    _selection = State(initialValue: initialSelection)
  }

  private var current: [SeriesResult] { series.filter { !$0.isPrevious } }
  private var previous: [SeriesResult] { series.filter(\.isPrevious) }
  private var bucketCount: Int { series.map(\.data.count).max() ?? 0 }

  public var body: some View {
    if let onSelectPoint {
      axedChart
        .chartOverlay { proxy in
          GeometryReader { geometry in
            indicator(proxy: proxy, geometry: geometry)
            touchTarget(proxy: proxy, geometry: geometry, onSelectPoint: onSelectPoint)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction(named: Text("See the people")) {
          guard bucketCount > 0 else { return }
          onSelectPoint(bucketCount - 1, 0)
        }
    } else {
      axedChart
        .accessibilityLabel(accessibilitySummary)
    }
  }

  private var axedChart: some View {
    styledChart
      .chartXAxis {
        if showsAxes {
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
      }
      .chartYAxis {
        if showsAxes {
          AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine().foregroundStyle(PHColor.divider)
            AxisValueLabel()
              .font(.caption2)
              .foregroundStyle(PHColor.textTertiary)
          }
        }
      }
  }

  /// One `Chart` per style. Switching *inside* the chart-content builder would
  /// need `_ConditionalContent`, whose `ChartContent` conformance the SDK gates
  /// to a far newer iOS than this app deploys to; switching at the view level
  /// does not.
  @ViewBuilder
  private var styledChart: some View {
    switch style {
    case .line:
      Chart {
        previousMarks
        currentLineMarks
      }
    case .area:
      Chart {
        previousMarks
        currentAreaMarks
      }
    case .bar:
      Chart {
        previousMarks
        currentBarMarks
      }
    }
  }

  @ChartContentBuilder
  private var previousMarks: some ChartContent {
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
  }

  @ChartContentBuilder
  private var currentLineMarks: some ChartContent {
    ForEach(Array(current.enumerated()), id: \.offset) { seriesIndex, one in
      ForEach(Array(one.data.enumerated()), id: \.offset) { index, value in
        LineMark(
          x: .value("Bucket", index),
          y: .value("Value", value),
          series: .value("Series", one.label + String(seriesIndex))
        )
        .foregroundStyle(PHColor.series(at: seriesIndex))
        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .interpolationMethod(.catmullRom)
      }
    }
  }

  @ChartContentBuilder
  private var currentAreaMarks: some ChartContent {
    ForEach(Array(current.enumerated()), id: \.offset) { seriesIndex, one in
      ForEach(Array(one.data.enumerated()), id: \.offset) { index, value in
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
      }
    }
  }

  @ChartContentBuilder
  private var currentBarMarks: some ChartContent {
    ForEach(Array(current.enumerated()), id: \.offset) { seriesIndex, one in
      ForEach(Array(one.data.enumerated()), id: \.offset) { index, value in
        BarMark(x: .value("Bucket", index), y: .value("Value", value))
          .foregroundStyle(PHColor.series(at: seriesIndex))
          .cornerRadius(3)
      }
    }
  }

  /// Where the vertical rule and the emphasized dot land, in overlay coordinates.
  private struct IndicatorSpot {
    let rect: CGRect
    let x: CGFloat
    let y: CGFloat
    let series: Int
  }

  /// The vertical rule plus the dot on the touched series.
  @ViewBuilder
  private func indicator(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
    if let spot = indicatorSpot(proxy: proxy, geometry: geometry) {
      Rectangle()
        .fill(PHColor.textPrimary.opacity(0.16))
        .frame(width: 1, height: spot.rect.height)
        .position(x: spot.rect.minX + spot.x, y: spot.rect.midY)
      Circle()
        .fill(PHColor.series(at: spot.series))
        .frame(width: 9, height: 9)
        .overlay(Circle().strokeBorder(PHColor.background, lineWidth: 2))
        .position(x: spot.rect.minX + spot.x, y: spot.rect.minY + spot.y)
    }
  }

  private func indicatorSpot(proxy: ChartProxy, geometry: GeometryProxy) -> IndicatorSpot? {
    guard let selection,
      let plotFrame = proxy.plotFrame,
      let xPosition = proxy.position(forX: selection.bucket),
      let value = pointValue(selection),
      let yPosition = proxy.position(forY: value)
    else { return nil }
    return IndicatorSpot(
      rect: geometry[plotFrame],
      x: xPosition,
      y: yPosition,
      series: selection.series
    )
  }

  private func touchTarget(
    proxy: ChartProxy,
    geometry: GeometryProxy,
    onSelectPoint: @escaping (Int, Int) -> Void
  ) -> some View {
    Rectangle()
      .fill(Color.clear)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            selection = resolveSelection(at: drag.location, proxy: proxy, geometry: geometry)
          }
          .onEnded { drag in
            let hit = resolveSelection(at: drag.location, proxy: proxy, geometry: geometry)
            selection = nil
            guard let hit else { return }
            onSelectPoint(hit.bucket, hit.series)
          }
      )
  }

  private func resolveSelection(
    at location: CGPoint,
    proxy: ChartProxy,
    geometry: GeometryProxy
  ) -> Selection? {
    guard bucketCount > 0, let plotFrame = proxy.plotFrame else { return nil }
    let rect = geometry[plotFrame]
    guard let raw = proxy.value(atX: location.x - rect.minX, as: Double.self) else { return nil }
    let bucket = min(max(Int(raw.rounded()), 0), bucketCount - 1)
    let seriesIndex = nearestSeries(toY: location.y - rect.minY, bucket: bucket, proxy: proxy)
    return Selection(bucket: bucket, series: seriesIndex)
  }

  /// With one series there is nothing to disambiguate, so skip the y lookup.
  private func nearestSeries(toY yPosition: CGFloat, bucket: Int, proxy: ChartProxy) -> Int {
    guard current.count > 1, let target = proxy.value(atY: yPosition, as: Double.self) else {
      return 0
    }
    let distances = current.enumerated().compactMap { index, one -> (index: Int, gap: Double)? in
      guard one.data.indices.contains(bucket) else { return nil }
      return (index, abs(one.data[bucket] - target))
    }
    return distances.min { $0.gap < $1.gap }?.index ?? 0
  }

  private func pointValue(_ selection: Selection) -> Double? {
    guard current.indices.contains(selection.series) else { return nil }
    let data = current[selection.series].data
    guard data.indices.contains(selection.bucket) else { return nil }
    return data[selection.bucket]
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
