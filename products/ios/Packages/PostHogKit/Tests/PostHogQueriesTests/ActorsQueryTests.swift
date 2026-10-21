import Foundation
import PostHogFoundation
import Testing

@testable import PostHogQueries

private func actorsFixture(_ name: String) throws -> JSONValue {
  let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
  return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
}

private let trendsSource = DataQuery(raw: [
  "kind": "TrendsQuery",
  "series": [["kind": "EventsNode", "event": "$pageview", "math": "dau"]],
  "interval": "day",
  "dateRange": ["date_from": "-7d"],
])

private let funnelsSource = DataQuery(raw: [
  "kind": "FunnelsQuery",
  "series": [
    ["kind": "EventsNode", "event": "$pageview"],
    ["kind": "EventsNode", "event": "signed up"],
  ],
])

@Suite struct ActorsQueryBuilderTests {
  @Test func trendsPointScopesTheQueryAndUnwrapsTheVizWrapper() throws {
    let saved = DataQuery(raw: [
      "kind": "InsightVizNode",
      "source": trendsSource.raw,
      "vizSpecificOptions": ["showLegend": true],
    ])
    let query = ActorsQueryBuilder.make(
      source: saved,
      drill: .trendsPoint(day: "2026-02-11", series: 1, breakdown: nil, compare: nil)
    )

    let outer = try #require(query.raw.objectValue)
    #expect(Set(outer.keys) == ["kind", "source", "select", "limit", "offset"])
    #expect(outer["kind"]?.stringValue == "ActorsQuery")
    #expect(outer["select"]?.arrayValue?.compactMap(\.stringValue) == ["person", "created_at"])
    #expect(outer["limit"]?.intValue == 100)
    #expect(outer["offset"]?.intValue == 0)

    let inner = try #require(outer["source"]?.objectValue)
    // `compare` was nil, so its key must be absent rather than null.
    #expect(Set(inner.keys) == ["kind", "source", "day", "series"])
    #expect(inner["kind"]?.stringValue == "InsightActorsQuery")
    #expect(inner["day"]?.stringValue == "2026-02-11")
    #expect(inner["series"]?.intValue == 1)
    // The wrapper is gone and the bare insight rode through intact.
    #expect(inner["source"]?["kind"]?.stringValue == "TrendsQuery")
    #expect(inner["source"]?["interval"]?.stringValue == "day")
    #expect(inner["source"]?["vizSpecificOptions"] == nil)
  }

  @Test func trendsPointCarriesTheComparisonPeriod() throws {
    let query = ActorsQueryBuilder.make(
      source: trendsSource,
      drill: .trendsPoint(day: "2026-02-11", series: nil, breakdown: nil, compare: "previous")
    )
    let inner = try #require(query.raw["source"]?.objectValue)
    #expect(Set(inner.keys) == ["kind", "source", "day", "compare"])
    #expect(inner["compare"]?.stringValue == "previous")
  }

  /// A breakdown chart's rows are one per breakdown value, so the drill scopes
  /// by that value rather than by a row position.
  @Test func trendsPointCarriesTheBreakdownValue() throws {
    let query = ActorsQueryBuilder.make(
      source: trendsSource,
      drill: .trendsPoint(day: "2026-02-11", series: nil, breakdown: "Safari", compare: nil)
    )
    let inner = try #require(query.raw["source"]?.objectValue)
    #expect(Set(inner.keys) == ["kind", "source", "day", "breakdown"])
    #expect(inner["breakdown"]?.stringValue == "Safari")
  }

  @Test func funnelStepRoutesToTheFunnelsActorsNodeAndCountsFromOne() throws {
    let query = ActorsQueryBuilder.make(source: funnelsSource, drill: .funnelStep(order: 0))
    let inner = try #require(query.raw["source"]?.objectValue)
    #expect(Set(inner.keys) == ["kind", "source", "funnelStep"])
    #expect(inner["kind"]?.stringValue == "FunnelsActorsQuery")
    // The first step is `order` 0 here and `funnelStep` 1 on the wire. Sending
    // 0 asks for no step at all.
    #expect(inner["funnelStep"]?.intValue == 1)
    #expect(inner["source"]?["kind"]?.stringValue == "FunnelsQuery")
  }

  /// A funnel-step drill can reach a source that is not a funnel, and neither
  /// drill may leave a scoping key behind on the plain node.
  @Test(arguments: [ActorsDrill.aggregate, .funnelStep(order: 1)])
  func nonFunnelDrillsFallBackToThePlainInsightActorsNode(_ drill: ActorsDrill) throws {
    let query = ActorsQueryBuilder.make(source: trendsSource, drill: drill, limit: 20, offset: 40)
    let outer = try #require(query.raw.objectValue)
    #expect(outer["limit"]?.intValue == 20)
    #expect(outer["offset"]?.intValue == 40)

    let inner = try #require(outer["source"]?.objectValue)
    #expect(Set(inner.keys) == ["kind", "source"])
    #expect(inner["kind"]?.stringValue == "InsightActorsQuery")
    #expect(inner["source"]?["kind"]?.stringValue == "TrendsQuery")
  }

  @Test func retentionCellSelectsTheCohortRowNotTheColumn() throws {
    let retention = DataQuery(raw: [
      "kind": "RetentionQuery",
      "retentionFilter": ["period": "Week", "totalIntervals": 8],
    ])
    let query = ActorsQueryBuilder.make(
      source: retention,
      drill: .retentionCell(cohortIndex: 2, intervalIndex: 3)
    )
    let inner = try #require(query.raw["source"]?.objectValue)
    #expect(Set(inner.keys) == ["kind", "source", "interval"])
    #expect(inner["kind"]?.stringValue == "InsightActorsQuery")
    // The web app sends the cohort row index here, so 2 rather than 3. Sending
    // the column index would return a different cohort's people.
    #expect(inner["interval"]?.intValue == 2)
    #expect(inner["source"]?["kind"]?.stringValue == "RetentionQuery")
  }

  @Test(
    arguments: zip(
      [nil, "", "ada@example.com"] as [String?],
      [nil, nil, "ada@example.com"] as [String?]
    )
  )
  func searchRidesAlongOnlyWhenItHasText(_ search: String?, _ expected: String?) {
    let query = ActorsQueryBuilder.make(source: trendsSource, drill: .aggregate, search: search)
    #expect(query.raw["search"]?.stringValue == expected)
  }
}

@Suite struct ActorsPageTests {
  @Test func parsesAPageAndNamesEveryPersonByPrecedence() throws {
    let body = try actorsFixture("actors-response")
    let page = try #require(ActorsPage.parse(body))

    #expect(page.columns == ["person", "created_at"])
    #expect(page.hasMore == true)
    #expect(page.hogql?.hasPrefix("SELECT persons.id") == true)
    #expect(page.missingActorsCount == 3)

    #expect(page.rows.count == 4)
    #expect(
      page.rows.map(\.displayName) == [
        "ada@example.com",  // email wins
        "Rowan Pike",  // empty email falls through to the name
        "kiosk-7g8h9i",  // no email or name, so the first distinct id
        "Anonymous user",  // nothing usable to show
      ]
    )
    #expect(page.rows[0].id == "0198c4a1-0000-4000-8000-000000000001")
    #expect(page.rows[0].distinctID == "seat-1a2b3c")
    #expect(page.rows[0].properties?["$browser"]?.stringValue == "Safari")
    #expect(page.rows[2].distinctID == "kiosk-7g8h9i")
    // The last person carries `uuid` instead of `id`.
    #expect(page.rows[3].id == "0198c4a1-0000-4000-8000-000000000004")
    #expect(page.rows[3].distinctID == nil)
  }

  @Test func readsThePersonColumnByNameAndDropsUnusableRows() throws {
    let body: JSONValue = [
      "columns": ["created_at", "person"],
      "results": [
        ["2026-02-11T00:00:00Z", ["id": "0198c4a1-1", "distinct_ids": ["seat-1a2b3c"]]],
        ["2026-02-12T00:00:00Z", ["distinct_ids": ["seat-4d5e6f"]]],
        ["2026-02-13T00:00:00Z", "not-a-person"],
        [],
      ],
    ]
    let page = try #require(ActorsPage.parse(body))

    #expect(page.rows.count == 1)
    #expect(page.rows[0].id == "0198c4a1-1")
    #expect(page.rows[0].displayName == "seat-1a2b3c")
    #expect(page.hasMore == false)
    #expect(page.hogql == nil)
    #expect(page.missingActorsCount == 0)
  }

  @Test(
    arguments: [
      JSONValue.null,
      .string("results"),
      .array([]),
      ["results": "not-an-array"],
      ["columns": ["person"], "hasMore": true],
    ] as [JSONValue]
  )
  func junkBodyReturnsNil(_ body: JSONValue) {
    #expect(ActorsPage.parse(body) == nil)
  }
}
