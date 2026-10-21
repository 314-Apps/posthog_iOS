import PostHogQueries
import SwiftUI

/// The one entry point for turning a query + result into pixels.
/// Every supported kind renders natively; anything else gets an honest
/// "Open in PostHog" tile instead of a broken chart.
public struct InsightRenderer: View {
  private let query: DataQuery
  private let result: QueryResult
  private let onOpenInPostHog: (() -> Void)?
  private let onDrill: ((ActorsDrill) -> Void)?
  private let onInspect: (() -> Void)?

  public init(
    query: DataQuery,
    result: QueryResult,
    onOpenInPostHog: (() -> Void)? = nil,
    onDrill: ((ActorsDrill) -> Void)? = nil,
    onInspect: (() -> Void)? = nil
  ) {
    self.query = query
    self.result = result
    self.onOpenInPostHog = onOpenInPostHog
    self.onDrill = onDrill
    self.onInspect = onInspect
  }

  private var display: String? {
    guard case .trends(let trends) = query.renderSource else { return nil }
    return trends.display
  }

  public var body: some View {
    switch result {
    case .series(let series):
      if display == "BoldNumber" {
        BigNumberView(series: series, onSelect: aggregateHandler)
      } else {
        TrendsChartView(
          series: series,
          style: TrendsChartView.Style(display: display),
          onSelectPoint: trendsPointHandler(series: series)
        )
        .frame(minHeight: 160)
      }
    case .funnel(let steps):
      FunnelChartView(steps: steps, onSelectStep: funnelStepHandler)
    case .retention(let rows):
      RetentionGridView(rows: rows, onSelectCell: retentionCellHandler)
    case .webOverview(let items):
      WebOverviewGridView(items: items, onSelectItem: inspectHandler.map { open in { _ in open() } })
    case .table(let table):
      TableResultView(table: table, onSelectRow: inspectHandler.map { open in { _ in open() } })
    case .unknown:
      UnsupportedInsightTile(kind: query.renderSource.kind, onOpen: onOpenInPostHog)
    }
  }

  /// Web overview tiles and table rows count things that are not always
  /// people, so they open the query behind the number instead of a person list.
  private var inspectHandler: (() -> Void)? { onInspect }

  private var aggregateHandler: (() -> Void)? {
    guard let onDrill else { return nil }
    return { onDrill(.aggregate) }
  }

  /// The comparison series is drawn but not drillable, so a point always
  /// resolves to the current period.
  private func trendsPointHandler(series: [SeriesResult]) -> ((Int, Int) -> Void)? {
    guard let onDrill else { return nil }
    return { bucketIndex, seriesIndex in
      let tapped = seriesIndex < series.count ? series[seriesIndex] : nil
      let breakdown = tapped?.breakdownValue
      onDrill(
        .trendsPoint(
          day: TrendsBucketResolver.day(for: bucketIndex, in: series),
          // A breakdown response holds one row per breakdown value, so the
          // row's position is not a series number. Where the response does not
          // name the series, the breakdown alone scopes the drill.
          series: tapped?.actionOrder ?? (breakdown == nil ? seriesIndex : nil),
          breakdown: breakdown,
          compare: "current"
        )
      )
    }
  }

  private var funnelStepHandler: ((Int) -> Void)? {
    guard let onDrill else { return nil }
    return { order in onDrill(.funnelStep(order: order)) }
  }

  private var retentionCellHandler: ((Int, Int) -> Void)? {
    guard let onDrill else { return nil }
    return { cohortIndex, intervalIndex in
      onDrill(.retentionCell(cohortIndex: cohortIndex, intervalIndex: intervalIndex))
    }
  }
}

/// The graceful fallback for query kinds the app does not render natively yet.
public struct UnsupportedInsightTile: View {
  private let kind: String
  private let onOpen: (() -> Void)?

  public init(kind: String, onOpen: (() -> Void)? = nil) {
    self.kind = kind
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: PHSpacing.md) {
      Image(systemName: "chart.bar.doc.horizontal")
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(PHColor.textTertiary)
      Text("This insight renders on the web")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PHColor.textSecondary)
      if let onOpen {
        Button(action: onOpen) {
          Text("Open in PostHog")
            .font(.footnote.weight(.bold))
            .foregroundStyle(PHColor.link)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 140)
  }
}
