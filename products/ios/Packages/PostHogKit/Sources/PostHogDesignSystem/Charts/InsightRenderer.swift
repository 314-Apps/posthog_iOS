import PostHogQueries
import SwiftUI

/// The one entry point for turning a query + result into pixels.
/// Every supported kind renders natively; anything else gets an honest
/// "Open in PostHog" tile instead of a broken chart.
public struct InsightRenderer: View {
  private let query: DataQuery
  private let result: QueryResult
  private let onOpenInPostHog: (() -> Void)?

  public init(query: DataQuery, result: QueryResult, onOpenInPostHog: (() -> Void)? = nil) {
    self.query = query
    self.result = result
    self.onOpenInPostHog = onOpenInPostHog
  }

  private var display: String? {
    guard case .trends(let trends) = query.renderSource else { return nil }
    return trends.display
  }

  public var body: some View {
    switch result {
    case .series(let series):
      if display == "BoldNumber" {
        BigNumberView(series: series)
      } else {
        TrendsChartView(series: series, style: TrendsChartView.Style(display: display))
          .frame(minHeight: 160)
      }
    case .funnel(let steps):
      FunnelChartView(steps: steps)
    case .retention(let rows):
      RetentionGridView(rows: rows)
    case .webOverview(let items):
      WebOverviewGridView(items: items)
    case .table(let table):
      TableResultView(table: table)
    case .unknown:
      UnsupportedInsightTile(kind: query.renderSource.kind, onOpen: onOpenInPostHog)
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
