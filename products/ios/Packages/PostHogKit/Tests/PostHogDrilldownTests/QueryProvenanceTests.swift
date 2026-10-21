import PostHogFoundation
import PostHogQueries
import Testing

@testable import PostHogDrilldown

@Suite struct QueryProvenanceTests {
  @Test func readsTheFieldsAnInsightCarries() {
    let query = DataQuery(raw: [
      "kind": "InsightVizNode",
      "source": [
        "kind": "TrendsQuery",
        "interval": "week",
        "dateRange": ["date_from": "-30d", "date_to": "-1d"],
        "series": [
          ["kind": "EventsNode", "event": "signup_completed", "custom_name": "Signups"],
          ["kind": "EventsNode", "event": "invoice_paid"],
          ["kind": "EventsNode", "event": .null],
        ],
      ],
    ])
    let provenance = QueryProvenance(query: query)

    #expect(provenance.kindLabel == "Trends")
    #expect(provenance.dateFrom == "-30d")
    #expect(provenance.dateTo == "-1d")
    #expect(provenance.dateRangeText == "-30d to -1d")
    #expect(provenance.interval == "week")
    #expect(provenance.seriesNames == ["Signups", "invoice_paid", "All events"])
  }

  @Test func anOpenEndedRangeReadsAsRunningToNow() {
    let query = DataQuery(raw: [
      "kind": "FunnelsQuery",
      "dateRange": ["date_from": "-14d"],
    ])
    let provenance = QueryProvenance(query: query)

    #expect(provenance.kindLabel == "Funnel")
    #expect(provenance.dateRangeText == "-14d to now")
    #expect(provenance.seriesNames.isEmpty)
  }

  @Test(
    arguments: [
      (JSONValue.string("not a query at all"), "Unknown query"),
      (["kind": ""], "Unknown query"),
      (["kind": "TrendsQuery", "dateRange": "yesterday", "interval": ["day"], "series": 7], "Trends"),
      (["kind": "ErrorTrackingQuery"], "Error tracking"),
    ] as [(JSONValue, String)]
  )
  func unexpectedShapesStillProduceALabelAndNothingElse(raw: JSONValue, expectedLabel: String) {
    let provenance = QueryProvenance(query: DataQuery(raw: raw))

    #expect(provenance.kindLabel == expectedLabel)
    #expect(provenance.dateRangeText == nil)
    #expect(provenance.interval == nil)
    #expect(provenance.seriesNames.isEmpty)
  }
}
