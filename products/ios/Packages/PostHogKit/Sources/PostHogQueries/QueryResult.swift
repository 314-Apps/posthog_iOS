import Foundation
import PostHogFoundation

/// A rendered-ready query response, mapped per query kind. Anything the app
/// cannot type keeps its raw payload.
public enum QueryResult: Sendable, Equatable {
  case series([SeriesResult])
  case funnel([FunnelStep])
  case retention([RetentionRow])
  case webOverview([WebOverviewItem])
  case table(TableResult)
  case unknown(JSONValue)

  /// Maps a completed response body for the query kind that produced it.
  public static func parse(kind: String, body: JSONValue) -> QueryResult {
    switch kind {
    case "TrendsQuery", "LifecycleQuery", "StickinessQuery":
      guard let rows = body["results"]?.arrayValue else { return .unknown(body) }
      return .series(rows.compactMap(SeriesResult.init(raw:)))
    case "FunnelsQuery":
      guard let rows = body["results"]?.arrayValue else { return .unknown(body) }
      // Breakdown funnels nest arrays; flatten the first breakdown for now.
      if let first = rows.first, first.arrayValue != nil {
        let flattened = rows.flatMap { $0.arrayValue ?? [] }
        return .funnel(flattened.compactMap(FunnelStep.init(raw:)))
      }
      return .funnel(rows.compactMap(FunnelStep.init(raw:)))
    case "RetentionQuery":
      guard let rows = body["results"]?.arrayValue else { return .unknown(body) }
      return .retention(rows.compactMap(RetentionRow.init(raw:)))
    case "WebOverviewQuery":
      guard let rows = body["results"]?.arrayValue else { return .unknown(body) }
      return .webOverview(rows.compactMap(WebOverviewItem.init(raw:)))
    case "HogQLQuery", "EventsQuery":
      return TableResult(raw: body).map(QueryResult.table) ?? .unknown(body)
    default:
      return .unknown(body)
    }
  }
}

/// One trends/lifecycle/stickiness series.
public struct SeriesResult: Sendable, Equatable {
  public let label: String
  public let data: [Double]
  public let labels: [String]
  public let days: [String]
  public let count: Double
  public let aggregatedValue: Double?
  public let compareLabel: String?
  public let breakdownValue: String?
  /// Which of the source query's series this row came from. Absent on
  /// responses that do not name it, and on a breakdown row it is the only way
  /// to tell, because the rows are one per breakdown value rather than one per
  /// series.
  public let actionOrder: Int?

  init?(raw: JSONValue) {
    guard let object = raw.objectValue else { return nil }
    self.label = object["label"]?.stringValue ?? ""
    self.data = object["data"]?.arrayValue?.compactMap(\.numberValue) ?? []
    self.labels = object["labels"]?.arrayValue?.compactMap(\.stringValue) ?? []
    self.days = object["days"]?.arrayValue?.compactMap(\.stringValue) ?? []
    self.count = object["count"]?.numberValue ?? data.reduce(0, +)
    self.aggregatedValue = object["aggregated_value"]?.numberValue
    self.compareLabel = object["compare_label"]?.stringValue
    self.breakdownValue = object["breakdown_value"]?.stringValue
    self.actionOrder = object["action"]?["order"]?.intValue
  }

  public var isPrevious: Bool { compareLabel == "previous" }
}

public struct FunnelStep: Sendable, Equatable {
  public let order: Int
  public let name: String
  public let customName: String?
  public let count: Double
  public let averageConversionTime: Double?

  init?(raw: JSONValue) {
    guard let object = raw.objectValue else { return nil }
    self.order = object["order"]?.intValue ?? 0
    self.name = object["name"]?.stringValue ?? ""
    self.customName = object["custom_name"]?.stringValue
    self.count = object["count"]?.numberValue ?? 0
    self.averageConversionTime = object["average_conversion_time"]?.numberValue
  }

  public var displayName: String { customName ?? name }
}

public struct RetentionRow: Sendable, Equatable {
  public let label: String
  public let date: String?
  public let counts: [Double]

  init?(raw: JSONValue) {
    guard let object = raw.objectValue else { return nil }
    self.label = object["label"]?.stringValue ?? ""
    self.date = object["date"]?.stringValue
    self.counts = object["values"]?.arrayValue?.compactMap { $0["count"]?.numberValue } ?? []
  }
}

/// One web-overview stat tile.
public struct WebOverviewItem: Sendable, Equatable {
  public enum Unit: String, Sendable {
    case unit
    case percentage
    case durationSeconds = "duration_s"
    case currency
  }

  public let key: String
  public let value: Double?
  public let previous: Double?
  public let changeFromPreviousPct: Double?
  public let unit: Unit
  public let isIncreaseBad: Bool

  init?(raw: JSONValue) {
    guard let object = raw.objectValue, let key = object["key"]?.stringValue else { return nil }
    self.key = key
    self.value = object["value"]?.numberValue
    self.previous = object["previous"]?.numberValue
    self.changeFromPreviousPct = object["changeFromPreviousPct"]?.numberValue
    self.unit = object["kind"]?.stringValue.flatMap(Unit.init(rawValue:)) ?? .unit
    self.isIncreaseBad = object["isIncreaseBad"]?.boolValue ?? false
  }
}

/// Columnar HogQL/events results.
public struct TableResult: Sendable, Equatable {
  public let columns: [String]
  public let rows: [[JSONValue]]
  public let hasMore: Bool

  init?(raw: JSONValue) {
    guard let results = raw["results"]?.arrayValue else { return nil }
    self.columns = raw["columns"]?.arrayValue?.compactMap(\.stringValue) ?? []
    self.rows = results.map { $0.arrayValue ?? [$0] }
    self.hasMore = raw["hasMore"]?.boolValue ?? false
  }
}
