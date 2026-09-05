import PostHogFoundation
import PostHogQueries
import Testing

@testable import PostHogDesignSystem

@Suite
struct TrendsBucketResolverTests {
  @Test func prefersTheISODateOverTheDisplayLabel() {
    let series = fixture(days: ["2026-03-12", "2026-03-13"], labels: ["12-Mar", "13-Mar"])
    #expect(TrendsBucketResolver.day(for: 1, in: series) == "2026-03-13")
  }

  @Test func fallsBackToTheDisplayLabel() {
    let series = fixture(days: [], labels: ["12-Mar", "13-Mar"])
    #expect(TrendsBucketResolver.day(for: 0, in: series) == "12-Mar")
  }

  @Test func returnsNothingWhenTheSeriesCarriesNeither() {
    #expect(TrendsBucketResolver.day(for: 0, in: fixture(days: [], labels: [])) == nil)
  }

  @Test(arguments: [-1, 2, 99])
  func returnsNothingOutsideTheBuckets(index: Int) {
    let series = fixture(days: ["2026-03-12", "2026-03-13"], labels: ["12-Mar", "13-Mar"])
    #expect(TrendsBucketResolver.day(for: index, in: series) == nil)
  }

  @Test func datesFromTheCurrentSeriesNotTheComparison() {
    let body: JSONValue = [
      "results": [
        [
          "label": "user signed up", "count": 2, "data": [1, 2],
          "labels": [], "days": ["2026-03-05", "2026-03-06"], "compare_label": "previous",
        ],
        [
          "label": "user signed up", "count": 2, "data": [3, 4],
          "labels": [], "days": ["2026-03-12", "2026-03-13"], "compare_label": "current",
        ],
      ]
    ]
    guard case .series(let parsed) = QueryResult.parse(kind: "TrendsQuery", body: body) else {
      Issue.record("fixture parse failed")
      return
    }
    #expect(TrendsBucketResolver.day(for: 0, in: parsed) == "2026-03-12")
  }

  private func fixture(days: [String], labels: [String]) -> [SeriesResult] {
    let body: JSONValue = [
      "results": [
        [
          "label": "user signed up",
          "count": 2,
          "data": [1, 2],
          "labels": .array(labels.map(JSONValue.string)),
          "days": .array(days.map(JSONValue.string)),
          "compare_label": "current",
        ]
      ]
    ]
    guard case .series(let parsed) = QueryResult.parse(kind: "TrendsQuery", body: body) else {
      return []
    }
    return parsed
  }
}
