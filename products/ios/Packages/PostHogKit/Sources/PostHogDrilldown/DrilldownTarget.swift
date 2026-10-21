import Foundation
import PostHogQueries
import SwiftUI

/// One tap on a metric, resolved: the query it came from and the part of it the
/// person reached for. Identifiable so a `.sheet(item:)` reopens when the
/// person taps a different point without closing the sheet first.
public struct DrilldownTarget: Identifiable, Sendable {
  public let id = UUID()
  public let source: DataQuery
  public let drill: ActorsDrill
  public let title: String

  public init(source: DataQuery, drill: ActorsDrill, title: String? = nil) {
    self.source = source
    self.drill = drill
    self.title = title ?? Self.defaultTitle(for: drill)
  }

  /// Names the group of people without repeating a number the sheet is about to
  /// show, and without a step or cohort ordinal the person cannot check.
  static func defaultTitle(for drill: ActorsDrill) -> String {
    switch drill {
    case .aggregate:
      return "People"
    case .trendsPoint(let day, _, _, _):
      guard let day, let date = Self.date(from: day) else { return "People" }
      // A bucket names a calendar date, not an instant, so it is read and
      // written in the same zone. Formatting it locally moves the label to the
      // day before for anyone west of UTC.
      var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
      style.timeZone = Self.bucketTimeZone
      return "People on \(date.formatted(style))"
    case .funnelStep:
      return "People at this step"
    case .retentionCell:
      return "People in this cohort"
    }
  }

  private static let bucketTimeZone = TimeZone.gmt

  /// Trends label days as `2026-02-11`, and as `2026-02-11 00:00:00` on an
  /// hourly interval. Read the date off the front of either.
  private static func date(from day: String) -> Date? {
    let prefix = String(day.prefix(10))
    return try? Date(
      prefix,
      strategy: .iso8601.year().month().day().dateSeparator(.dash)
    )
  }
}

/// One query a person asked to see behind. Identifiable so reaching for a
/// second tile swaps the sheet rather than doing nothing.
public struct QueryInspection: Identifiable, Sendable {
  public let id = UUID()
  public let query: DataQuery
  public let hogql: String?

  public init(query: DataQuery, hogql: String? = nil) {
    self.query = query
    self.hogql = hogql
  }
}

extension View {
  /// Presents the people behind whatever the person tapped. Routing to a person
  /// belongs to the caller, because only the shell knows the navigation stack.
  public func actorsDrilldown(
    _ target: Binding<DrilldownTarget?>,
    context: ProjectContext,
    onOpenPerson: @escaping (String) -> Void
  ) -> some View {
    sheet(item: target) { target in
      ActorsSheet(
        context: context,
        source: target.source,
        drill: target.drill,
        title: target.title,
        onOpenPerson: onOpenPerson
      )
    }
  }

  /// Presents the query behind a number, for the surfaces whose totals do not
  /// resolve to a list of people.
  public func queryProvenance(_ item: Binding<QueryInspection?>) -> some View {
    sheet(item: item) { QueryProvenanceSheet(query: $0.query, hogql: $0.hogql) }
  }
}
