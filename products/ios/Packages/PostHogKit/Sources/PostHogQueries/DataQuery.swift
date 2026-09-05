import Foundation
import PostHogFoundation

/// The query union, discriminated on `kind`.
///
/// Every case carries the complete original JSON (`raw`) and encodes it back
/// verbatim, so re-POSTing a saved insight's query cannot strip fields the app
/// does not model. Typed accessors read from (and mutation helpers write into)
/// that raw payload. Kinds outside the allowlist decode to `.unknown` — never
/// an error — and render as an "Open in PostHog" tile.
public enum DataQuery: Sendable, Equatable {
  case trends(TrendsQuery)
  case funnels(FunnelsQuery)
  case retention(RetentionQuery)
  case lifecycle(LifecycleQuery)
  case stickiness(StickinessQuery)
  case paths(PathsQuery)
  case hogQL(HogQLQuery)
  case events(EventsQuery)
  case webOverview(WebOverviewQuery)
  case insightViz(InsightVizNode)
  case dataTable(DataTableNode)
  case unknown(kind: String, raw: JSONValue)

  public var kind: String {
    switch self {
    case .trends: "TrendsQuery"
    case .funnels: "FunnelsQuery"
    case .retention: "RetentionQuery"
    case .lifecycle: "LifecycleQuery"
    case .stickiness: "StickinessQuery"
    case .paths: "PathsQuery"
    case .hogQL: "HogQLQuery"
    case .events: "EventsQuery"
    case .webOverview: "WebOverviewQuery"
    case .insightViz: "InsightVizNode"
    case .dataTable: "DataTableNode"
    case .unknown(let kind, _): kind
    }
  }

  public var raw: JSONValue {
    switch self {
    case .trends(let query): query.raw
    case .funnels(let query): query.raw
    case .retention(let query): query.raw
    case .lifecycle(let query): query.raw
    case .stickiness(let query): query.raw
    case .paths(let query): query.raw
    case .hogQL(let query): query.raw
    case .events(let query): query.raw
    case .webOverview(let query): query.raw
    case .insightViz(let node): node.raw
    case .dataTable(let node): node.raw
    case .unknown(_, let raw): raw
    }
  }

  public init(raw: JSONValue) {
    let kind = raw["kind"]?.stringValue ?? ""
    switch kind {
    case "TrendsQuery": self = .trends(TrendsQuery(raw: raw))
    case "FunnelsQuery": self = .funnels(FunnelsQuery(raw: raw))
    case "RetentionQuery": self = .retention(RetentionQuery(raw: raw))
    case "LifecycleQuery": self = .lifecycle(LifecycleQuery(raw: raw))
    case "StickinessQuery": self = .stickiness(StickinessQuery(raw: raw))
    case "PathsQuery": self = .paths(PathsQuery(raw: raw))
    case "HogQLQuery": self = .hogQL(HogQLQuery(raw: raw))
    case "EventsQuery": self = .events(EventsQuery(raw: raw))
    case "WebOverviewQuery": self = .webOverview(WebOverviewQuery(raw: raw))
    case "InsightVizNode": self = .insightViz(InsightVizNode(raw: raw))
    case "DataTableNode": self = .dataTable(DataTableNode(raw: raw))
    default: self = .unknown(kind: kind, raw: raw)
    }
  }

  /// The query whose response gets rendered: unwraps InsightVizNode/DataTableNode.
  public var renderSource: DataQuery {
    switch self {
    case .insightViz(let node): node.source ?? self
    case .dataTable(let node): node.source ?? self
    default: self
    }
  }
}

extension DataQuery: Codable {
  public init(from decoder: Decoder) throws {
    self.init(raw: try JSONValue(from: decoder))
  }

  public func encode(to encoder: Encoder) throws {
    try raw.encode(to: encoder)
  }
}

// MARK: - Shared typed access

/// A query struct is a thin typed lens over its raw JSON.
public protocol RawBackedQuery: Sendable, Equatable {
  var raw: JSONValue { get set }
  init(raw: JSONValue)
}

extension RawBackedQuery {
  public var dateRange: DateRange? {
    get { raw["dateRange"].flatMap(DateRange.init(raw:)) }
    set { setField("dateRange", to: newValue?.rawValue ?? .null) }
  }

  public var interval: String? {
    get { raw["interval"]?.stringValue }
    set { setField("interval", to: newValue.map { .string($0) } ?? .null) }
  }

  public var compare: Bool {
    get { raw["compareFilter"]?["compare"]?.boolValue ?? false }
    set { setField("compareFilter", to: ["compare": .bool(newValue)]) }
  }

  mutating func setField(_ key: String, to value: JSONValue) {
    guard var object = raw.objectValue else { return }
    if value == .null {
      object.removeValue(forKey: key)
    } else {
      object[key] = value
    }
    raw = .object(object)
  }
}

/// `{date_from, date_to}` — relative forms like "-7d" and "dStart" included.
public struct DateRange: Sendable, Equatable {
  public var dateFrom: String?
  public var dateTo: String?

  public init(dateFrom: String?, dateTo: String? = nil) {
    self.dateFrom = dateFrom
    self.dateTo = dateTo
  }

  init?(raw: JSONValue) {
    guard raw.objectValue != nil else { return nil }
    self.dateFrom = raw["date_from"]?.stringValue
    self.dateTo = raw["date_to"]?.stringValue
  }

  var rawValue: JSONValue {
    var object: [String: JSONValue] = [:]
    if let dateFrom { object["date_from"] = .string(dateFrom) }
    if let dateTo { object["date_to"] = .string(dateTo) }
    return .object(object)
  }
}

// MARK: - Kinds

public struct TrendsQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }

  public var display: String? {
    raw["trendsFilter"]?["display"]?.stringValue
  }

  public var seriesCount: Int {
    raw["series"]?.arrayValue?.count ?? 0
  }

  /// Builder for the app's own preset queries (Home pulse).
  public static func make(
    series: [JSONValue],
    interval: String,
    dateFrom: String,
    compare: Bool = false,
    display: String? = nil
  ) -> TrendsQuery {
    var object: [String: JSONValue] = [
      "kind": "TrendsQuery",
      "series": .array(series),
      "interval": .string(interval),
      "dateRange": ["date_from": .string(dateFrom)],
    ]
    if compare {
      object["compareFilter"] = ["compare": true]
    }
    if let display {
      object["trendsFilter"] = ["display": .string(display)]
    }
    return TrendsQuery(raw: .object(object))
  }

  /// An all-events series node with a math aggregation ("dau", "weekly_active"…).
  public static func eventsNode(event: JSONValue = .null, math: String) -> JSONValue {
    ["kind": "EventsNode", "event": event, "math": .string(math)]
  }
}

public struct FunnelsQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct RetentionQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct LifecycleQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct StickinessQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct PathsQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct HogQLQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }

  public var query: String? { raw["query"]?.stringValue }

  public static func make(_ sql: String) -> HogQLQuery {
    HogQLQuery(raw: ["kind": "HogQLQuery", "query": .string(sql)])
  }
}

public struct EventsQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }
}

public struct WebOverviewQuery: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }

  public static func make(dateFrom: String, compare: Bool = true) -> WebOverviewQuery {
    var object: [String: JSONValue] = [
      "kind": "WebOverviewQuery",
      "dateRange": ["date_from": .string(dateFrom)],
      "properties": [],
    ]
    if compare {
      object["compareFilter"] = ["compare": true]
    }
    return WebOverviewQuery(raw: .object(object))
  }
}

public struct InsightVizNode: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }

  public var source: DataQuery? {
    get { raw["source"].map(DataQuery.init(raw:)) }
    set { setField("source", to: newValue?.raw ?? .null) }
  }
}

public struct DataTableNode: RawBackedQuery {
  public var raw: JSONValue
  public init(raw: JSONValue) { self.raw = raw }

  public var source: DataQuery? {
    get { raw["source"].map(DataQuery.init(raw:)) }
    set { setField("source", to: newValue?.raw ?? .null) }
  }
}
