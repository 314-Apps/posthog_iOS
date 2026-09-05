import PostHogFoundation
import PostHogQueries
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import PostHogDesignSystem

/// One snapshot per renderer × color scheme, on a fixed layout. Re-record with
/// `make snapshot-record` after intentional visual changes.
@MainActor
@Suite(.snapshots(record: .missing))
struct DesignSystemSnapshotTests {
  private func assert<Content: View>(
    _ view: Content,
    named name: String,
    width: CGFloat = 361,
    height: CGFloat = 240,
    testName: String = #function
  ) {
    for (scheme, suffix) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
      let host =
        view
        .padding(16)
        .background(PHColor.background)
      // Perceptual tolerance absorbs antialiasing drift across simulator
      // resets and Xcode point releases; real visual changes still fail.
      assertSnapshot(
        of: host,
        as: .image(
          precision: 0.97,
          perceptualPrecision: 0.97,
          layout: .fixed(width: width, height: height),
          traits: .init(userInterfaceStyle: scheme)
        ),
        named: "\(name)-\(suffix)",
        testName: testName
      )
    }
  }

  private var trendsSeries: [SeriesResult] {
    let body: JSONValue = [
      "results": [
        [
          "label": "user signed up",
          "count": 11573,
          "data": [1180, 1287, 1349, 1502, 1610, 2141, 2504],
          "labels": ["8-Mar", "9-Mar", "10-Mar", "11-Mar", "12-Mar", "13-Mar", "14-Mar"],
          "days": [],
          "compare_label": "current",
        ],
        [
          "label": "user signed up",
          "count": 9808,
          "data": [1101, 1189, 1240, 1355, 1422, 1698, 1803],
          "labels": [],
          "days": [],
          "compare_label": "previous",
        ],
      ]
    ]
    guard case .series(let series) = QueryResult.parse(kind: "TrendsQuery", body: body) else {
      return []
    }
    return series
  }

  @Test func trendsLineChart() {
    assert(TrendsChartView(series: trendsSeries, style: .line), named: "trends-line")
  }

  @Test func trendsBarChart() {
    assert(TrendsChartView(series: trendsSeries, style: .bar), named: "trends-bar")
  }

  /// The selection seed stands in for the drag gesture, which a headless render
  /// cannot deliver.
  @Test func trendsLineChartWithSelectedPoint() {
    assert(
      TrendsChartView(
        series: trendsSeries,
        style: .line,
        showsAxes: true,
        initialSelection: .init(bucket: 5, series: 0),
        onSelectPoint: { _, _ in }
      ),
      named: "trends-line-selected"
    )
  }

  @Test func bigNumber() {
    assert(BigNumberView(series: trendsSeries), named: "big-number", height: 130)
  }

  @Test func funnel() {
    let body: JSONValue = [
      "results": [
        ["name": "$pageview", "custom_name": "Viewed pricing", "order": 0, "count": 21406],
        ["name": "user signed up", "order": 1, "count": 11573],
        ["name": "subscription started", "order": 2, "count": 4918],
      ]
    ]
    guard case .funnel(let steps) = QueryResult.parse(kind: "FunnelsQuery", body: body) else {
      Issue.record("fixture parse failed")
      return
    }
    assert(FunnelChartView(steps: steps), named: "funnel", height: 200)
  }

  @Test func retention() {
    let body: JSONValue = [
      "results": [
        ["label": "Week 0", "values": [["count": 412], ["count": 181], ["count": 128], ["count": 107]]],
        ["label": "Week 1", "values": [["count": 388], ["count": 170], ["count": 121]]],
        ["label": "Week 2", "values": [["count": 441], ["count": 196]]],
      ]
    ]
    guard case .retention(let rows) = QueryResult.parse(kind: "RetentionQuery", body: body) else {
      Issue.record("fixture parse failed")
      return
    }
    assert(RetentionGridView(rows: rows), named: "retention", height: 130)
  }

  @Test func webOverview() {
    let body: JSONValue = [
      "results": [
        ["key": "visitors", "value": 48200, "changeFromPreviousPct": 5.1, "kind": "unit"],
        ["key": "views", "value": 131000, "changeFromPreviousPct": 2.4, "kind": "unit"],
        [
          "key": "bounce rate", "value": 38.0, "changeFromPreviousPct": -5.2,
          "kind": "percentage", "isIncreaseBad": true,
        ],
        ["key": "session duration", "value": 186.0, "changeFromPreviousPct": 3.9, "kind": "duration_s"],
      ]
    ]
    guard case .webOverview(let items) = QueryResult.parse(kind: "WebOverviewQuery", body: body) else {
      Issue.record("fixture parse failed")
      return
    }
    assert(WebOverviewGridView(items: items), named: "web-overview", height: 190)
  }

  @Test func componentsSampler() {
    let sampler = VStack(alignment: .leading, spacing: 12) {
      PHCard {
        VStack(alignment: .leading, spacing: 8) {
          PHCardLabel("Unique users · today")
          StatTile(label: "vs. yesterday", value: "12,847", deltaFraction: 0.124)
        }
      }
      HStack(spacing: 8) {
        FilterChip("7d", isSelected: true) {}
        FilterChip("30d", isSelected: false) {}
        FilterChip("Custom", isSelected: false) {}
      }
    }
    assert(sampler, named: "components", height: 220)
  }

  @Test func unsupportedTile() {
    assert(
      UnsupportedInsightTile(kind: "PathsQuery", onOpen: {}),
      named: "unsupported",
      height: 190
    )
  }

  @Test func emptyState() {
    assert(
      EmptyStateView(
        systemImage: "moon.zzz",
        title: "No events yet",
        message: "Install an SDK to start capturing events.",
        actionTitle: "Install an SDK",
        action: {}
      ),
      named: "empty-state",
      height: 300
    )
  }
}
