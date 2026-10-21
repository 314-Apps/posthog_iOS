import Foundation
import PostHogFoundation
import Testing

@testable import FeatureWeb

@Suite struct WebStatsRowsTests {
  private func body(_ json: String) -> JSONValue {
    (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null
  }

  @Test func columnsDriveCellOrdering() {
    let fixture = """
      {
        "columns": [
          "context.columns.views",
          "context.columns.breakdown_value",
          "context.columns.visitors"
        ],
        "results": [[204, "/pricing", 88], [90, "/docs", 41]]
      }
      """
    let rows = WebStatsRows.parse(body(fixture))
    #expect(
      rows == [
        WebStatsRow(label: "/pricing", visitors: 88, views: 204),
        WebStatsRow(label: "/docs", visitors: 41, views: 90),
      ])
  }

  @Test func namedColumnsWithoutVisitorsParseToNothing() {
    let fixture = """
      {
        "columns": ["context.columns.breakdown_value", "context.columns.bounce_rate"],
        "results": [["/pricing", 0.4]]
      }
      """
    #expect(WebStatsRows.parse(body(fixture)).isEmpty)
  }

  @Test func fallsBackToPositionalColumnsWhenUnnamed() {
    let fixture = #"{"results": [["/home", 120, 240], ["/docs", 40]]}"#
    let rows = WebStatsRows.parse(body(fixture))
    #expect(
      rows == [
        WebStatsRow(label: "/home", visitors: 120, views: 240),
        WebStatsRow(label: "/docs", visitors: 40, views: nil),
      ])
  }

  @Test func comparisonPairsUseTheCurrentValue() {
    let fixture = """
      {"results": [
        [["/checkout", null], [64, 51], [180, 122]],
        [null, [7, 9], [10, 11]]
      ]}
      """
    let rows = WebStatsRows.parse(body(fixture))
    #expect(
      rows == [
        WebStatsRow(label: "/checkout", visitors: 64, views: 180),
        WebStatsRow(label: "(none)", visitors: 7, views: 10),
      ])
  }

  @Test func nullBreakdownReadsAsNone() {
    let fixture = #"{"results": [[null, 12, 30]]}"#
    let rows = WebStatsRows.parse(body(fixture))
    #expect(rows == [WebStatsRow(label: "(none)", visitors: 12, views: 30)])
  }

  @Test func dropsJunkRows() {
    let fixture = """
      {"results": [
        {"not": "a row"},
        "junk",
        [null],
        ["/broken", "n/a", 3],
        ["/kept", 5, 8]
      ]}
      """
    let rows = WebStatsRows.parse(body(fixture))
    #expect(rows == [WebStatsRow(label: "/kept", visitors: 5, views: 8)])
    #expect(WebStatsRows.parse(body(#"{"error": "no results"}"#)).isEmpty)
    #expect(WebStatsRows.parse(.null).isEmpty)
  }
}
