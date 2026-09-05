import Foundation
import PostHogQueries
import Testing

@testable import PostHogDrilldown

private func title(_ drill: ActorsDrill) -> String {
  DrilldownTarget(source: DataQuery(raw: .object([:])), drill: drill).title
}

@Suite struct DrilldownTargetTests {
  @Test(
    arguments: [
      (ActorsDrill.aggregate, "People"),
      (.funnelStep(order: 0), "People at this step"),
      (.retentionCell(cohortIndex: 1, intervalIndex: 2), "People in this cohort"),
      // Nothing usable to name the day with, so the title says only what the
      // list is rather than showing a raw bucket string.
      (.trendsPoint(day: nil, series: 0, breakdown: nil, compare: nil), "People"),
      (.trendsPoint(day: "last week", series: nil, breakdown: nil, compare: nil), "People"),
    ] as [(ActorsDrill, String)]
  )
  func titlesNameTheGroupWithoutInventingAnOrdinal(_ drill: ActorsDrill, _ expected: String) {
    #expect(title(drill) == expected)
  }

  /// The month reads in the device's language, so this checks the day was
  /// parsed rather than the exact wording. An hourly bucket carries a time the
  /// title must drop.
  @Test(arguments: ["2026-02-11", "2026-02-11 00:00:00"])
  func aTrendsPointIsNamedByItsDay(_ day: String) {
    let named = title(.trendsPoint(day: day, series: nil, breakdown: nil, compare: nil))
    #expect(named.hasPrefix("People on "))
    #expect(named.contains("11"))
    #expect(!named.contains("00:00"))
  }

  @Test func aCallerCanNameTheGroupItself() {
    #expect(
      DrilldownTarget(
        source: DataQuery(raw: .object([:])),
        drill: .aggregate,
        title: "Signups today"
      ).title == "Signups today"
    )
  }
}
