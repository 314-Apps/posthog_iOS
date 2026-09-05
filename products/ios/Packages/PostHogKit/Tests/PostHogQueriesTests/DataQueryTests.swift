import Foundation
import PostHogFoundation
import Testing

@testable import PostHogQueries

private func fixture(_ name: String) throws -> Data {
  let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
  return try Data(contentsOf: url)
}

@Suite struct DataQueryTests {
  @Test func savedInsightRoundTripsLosslessly() throws {
    let data = try fixture("saved-insight-trends")
    let original = try JSONDecoder().decode(JSONValue.self, from: data)
    let query = try JSONDecoder().decode(DataQuery.self, from: data)
    let reencoded = try JSONEncoder().encode(query)
    let roundTripped = try JSONDecoder().decode(JSONValue.self, from: reencoded)
    #expect(roundTripped == original)
  }

  @Test func decodesNestedSourceKind() throws {
    let query = try JSONDecoder().decode(DataQuery.self, from: fixture("saved-insight-trends"))
    guard case .insightViz(let node) = query else {
      Issue.record("expected InsightVizNode, got \(query.kind)")
      return
    }
    #expect(query.renderSource.kind == "TrendsQuery")
    guard case .trends(let trends) = node.source else {
      Issue.record("expected TrendsQuery source")
      return
    }
    #expect(trends.interval == "week")
    #expect(trends.dateRange?.dateFrom == "-30d")
    #expect(trends.compare == true)
    #expect(trends.display == "ActionsLineGraph")
    #expect(trends.seriesCount == 1)
  }

  @Test func unknownKindNeverThrowsAndRoundTrips() throws {
    let raw = #"{"kind":"BrandNewQuery","mystery":{"deep":[1,2,3]},"limit":50}"#
    let query = try JSONDecoder().decode(DataQuery.self, from: Data(raw.utf8))
    guard case .unknown(let kind, _) = query else {
      Issue.record("expected .unknown, got \(query.kind)")
      return
    }
    #expect(kind == "BrandNewQuery")
    let reencoded = try JSONEncoder().encode(query)
    let original = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    let roundTripped = try JSONDecoder().decode(JSONValue.self, from: reencoded)
    #expect(roundTripped == original)
  }

  @Test func mutationHelpersPreserveUnmodeledFields() throws {
    let query = try JSONDecoder().decode(DataQuery.self, from: fixture("saved-insight-trends"))
    guard case .insightViz(var node) = query, case .trends(var trends) = node.source else {
      Issue.record("fixture shape changed")
      return
    }
    trends.dateRange = DateRange(dateFrom: "-7d")
    trends.interval = "day"
    trends.compare = false
    node.source = .trends(trends)

    #expect(trends.dateRange?.dateFrom == "-7d")
    #expect(trends.interval == "day")
    #expect(trends.compare == false)
    // The fields the app does not model must survive the mutation.
    let source = node.raw["source"]
    #expect(source?["breakdownFilter"]?["breakdown"]?.stringValue == "$browser")
    #expect(source?["samplingFactor"]?.numberValue == 0.5)
    #expect(source?["filterTestAccounts"]?.boolValue == true)
    #expect(node.raw["vizSpecificOptions"] != nil)
  }

  @Test func presetBuildersProduceValidQueries() {
    let dau = TrendsQuery.make(
      series: [TrendsQuery.eventsNode(math: "dau")],
      interval: "hour",
      dateFrom: "dStart",
      compare: true
    )
    #expect(dau.raw["kind"]?.stringValue == "TrendsQuery")
    #expect(dau.raw["series"]?[0]?["math"]?.stringValue == "dau")
    #expect(dau.compare == true)

    let web = WebOverviewQuery.make(dateFrom: "-7d")
    #expect(web.raw["kind"]?.stringValue == "WebOverviewQuery")
    #expect(web.dateRange?.dateFrom == "-7d")

    let sql = HogQLQuery.make("SELECT 1")
    #expect(sql.query == "SELECT 1")
  }
}

@Suite struct QueryResultTests {
  private func parse(_ fixtureName: String, kind: String) throws -> QueryResult {
    let body = try JSONDecoder().decode(JSONValue.self, from: fixture(fixtureName))
    return QueryResult.parse(kind: kind, body: body)
  }

  @Test func parsesTrendsSeriesWithComparison() throws {
    guard case .series(let series) = try parse("trends-response", kind: "TrendsQuery") else {
      Issue.record("expected series")
      return
    }
    #expect(series.count == 2)
    #expect(series[0].count == 11573)
    #expect(series[0].data.count == 7)
    #expect(series[0].isPrevious == false)
    #expect(series[1].isPrevious == true)
    #expect(series[0].days.first == "2026-03-08")
  }

  @Test func parsesFunnelSteps() throws {
    guard case .funnel(let steps) = try parse("funnels-response", kind: "FunnelsQuery") else {
      Issue.record("expected funnel")
      return
    }
    #expect(steps.count == 3)
    #expect(steps[0].displayName == "Viewed pricing")
    #expect(steps[1].displayName == "user signed up")
    #expect(steps[2].count == 4918)
    #expect(steps[1].averageConversionTime == 312.5)
  }

  @Test func parsesRetentionGrid() throws {
    guard case .retention(let rows) = try parse("retention-response", kind: "RetentionQuery") else {
      Issue.record("expected retention")
      return
    }
    #expect(rows.count == 3)
    #expect(rows[0].label == "Week 0")
    #expect(rows[0].counts == [412, 181, 128, 107])
    #expect(rows[2].counts.count == 2)
  }

  @Test func parsesWebOverviewItems() throws {
    guard case .webOverview(let items) = try parse("web-overview-response", kind: "WebOverviewQuery")
    else {
      Issue.record("expected webOverview")
      return
    }
    #expect(items.count == 5)
    #expect(items[0].key == "visitors")
    #expect(items[0].value == 48200)
    #expect(items[3].unit == .percentage)
    #expect(items[3].isIncreaseBad == true)
    #expect(items[4].unit == .durationSeconds)
  }

  @Test func parsesHogQLTable() throws {
    guard case .table(let table) = try parse("hogql-response", kind: "HogQLQuery") else {
      Issue.record("expected table")
      return
    }
    #expect(table.columns == ["event", "total"])
    #expect(table.rows.count == 3)
    #expect(table.rows[0][0].stringValue == "$pageview")
    #expect(table.hasMore == true)
  }

  @Test func unknownKindKeepsRawBody() throws {
    let body: JSONValue = ["surprise": true]
    guard case .unknown(let raw) = QueryResult.parse(kind: "PathsQuery", body: body) else {
      Issue.record("expected unknown")
      return
    }
    #expect(raw == body)
  }
}
