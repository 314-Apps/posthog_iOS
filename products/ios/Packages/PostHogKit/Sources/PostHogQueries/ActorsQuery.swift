import Foundation
import PostHogFoundation

/// Which part of a rendered insight the person tapped.
///
/// One case per drill the API models differently. `.aggregate` covers a single
/// headline number (a stat tile, a pie slice total) that scopes to nothing
/// narrower than the source query itself.
public enum ActorsDrill: Sendable, Equatable {
  case aggregate
  case trendsPoint(day: String?, series: Int?, breakdown: String?, compare: String?)
  /// `order` counts from zero, to match `FunnelStep.order`.
  case funnelStep(order: Int)
  case retentionCell(cohortIndex: Int, intervalIndex: Int)
}

/// Builds the `ActorsQuery` that answers "who is behind this number".
///
/// The shape mirrors what the web app POSTs when a chart is clicked: an outer
/// `ActorsQuery` that pages and searches, wrapped around an inner query that
/// scopes the source insight to the tapped cell. Keys the drill does not carry
/// are omitted rather than sent as null, because the API rejects a null where it
/// expects a string or an integer.
public enum ActorsQueryBuilder {
  public static func make(
    source: DataQuery,
    drill: ActorsDrill,
    limit: Int = 100,
    offset: Int = 0,
    search: String? = nil
  ) -> DataQuery {
    // A saved insight arrives wrapped in InsightVizNode/DataTableNode. The
    // actors source must be the bare insight query underneath.
    let insight = source.renderSource
    var object: [String: JSONValue] = [
      "kind": "ActorsQuery",
      "source": scopedSource(insight: insight, drill: drill),
      "select": ["person", "created_at"],
      "limit": .number(Double(limit)),
      "offset": .number(Double(offset)),
    ]
    if let search, !search.isEmpty {
      object["search"] = .string(search)
    }
    return DataQuery(raw: .object(object))
  }

  private static func scopedSource(insight: DataQuery, drill: ActorsDrill) -> JSONValue {
    // Funnel steps have their own node kind, but only a funnel source can feed
    // it. Any other source falls through to InsightActorsQuery, which the API
    // accepts, rather than to a node the server cannot run.
    if case .funnelStep(let order) = drill, case .funnels = insight {
      return [
        "kind": "FunnelsActorsQuery",
        "source": insight.raw,
        // The API numbers steps from 1, and reads a negative value as "dropped
        // off at this step" rather than "converted through it".
        "funnelStep": .number(Double(order + 1)),
      ]
    }

    var object: [String: JSONValue] = [
      "kind": "InsightActorsQuery",
      "source": insight.raw,
    ]
    switch drill {
    case .aggregate, .funnelStep:
      break
    case .trendsPoint(let day, let series, let breakdown, let compare):
      if let day { object["day"] = .string(day) }
      if let series { object["series"] = .number(Double(series)) }
      if let breakdown { object["breakdown"] = .string(breakdown) }
      if let compare { object["compare"] = .string(compare) }
    case .retentionCell(let cohortIndex, _):
      // `interval` selects the cohort row, not the column: the web app clicks a
      // whole row and sends its index here (see the web's retention modal
      // logic). One request returns that cohort's people with every
      // appearance, so the tapped column narrows the result on our side rather
      // than in the query.
      object["interval"] = .number(Double(cohortIndex))
    }
    return .object(object)
  }
}

/// One person behind a metric, as the actors response serves them.
public struct ActorRow: Sendable, Equatable, Identifiable {
  public let id: String
  public let displayName: String
  public let distinctID: String?
  public let properties: JSONValue?

  public init(id: String, displayName: String, distinctID: String?, properties: JSONValue?) {
    self.id = id
    self.displayName = displayName
    self.distinctID = distinctID
    self.properties = properties
  }

  init?(person: JSONValue) {
    guard let id = Self.identifier(in: person) else { return nil }
    let properties = person["properties"]
    let distinctID = person["distinct_ids"]?.arrayValue?
      .compactMap(\.stringValue)
      .first { !$0.isEmpty }
    self.id = id
    self.properties = properties
    self.distinctID = distinctID
    self.displayName = Self.displayName(properties: properties, distinctID: distinctID)
  }

  private static func identifier(in person: JSONValue) -> String? {
    for key in ["id", "uuid"] {
      guard let value = person[key] else { continue }
      if let text = value.stringValue, !text.isEmpty { return text }
      // The persons API serves a numeric id on some surfaces; accept it too.
      if let number = value.intValue { return String(number) }
    }
    return nil
  }

  /// Matches `PostHogAPI.Person.displayName` so a person reads the same in every
  /// list the app shows.
  private static func displayName(properties: JSONValue?, distinctID: String?) -> String {
    if let email = properties?["email"]?.stringValue, !email.isEmpty {
      return email
    }
    if let name = properties?["name"]?.stringValue, !name.isEmpty {
      return name
    }
    if let distinctID, !distinctID.isEmpty {
      return distinctID
    }
    return "Anonymous user"
  }
}

/// A page of an `ActorsQueryResponse`.
///
/// The response is columnar: `columns` names the selected expressions and each
/// row is an array positioned against it. Nothing here throws — the app renders
/// what it can read and drops the rest.
public struct ActorsPage: Sendable, Equatable {
  public let rows: [ActorRow]
  public let columns: [String]
  public let hasMore: Bool
  public let hogql: String?
  public let missingActorsCount: Int

  public init(
    rows: [ActorRow],
    columns: [String],
    hasMore: Bool,
    hogql: String?,
    missingActorsCount: Int
  ) {
    self.rows = rows
    self.columns = columns
    self.hasMore = hasMore
    self.hogql = hogql
    self.missingActorsCount = missingActorsCount
  }

  public static func parse(_ body: JSONValue) -> ActorsPage? {
    guard let results = body["results"]?.arrayValue else { return nil }
    let columns = body["columns"]?.arrayValue?.compactMap(\.stringValue) ?? []
    let personIndex = columns.firstIndex(of: "person") ?? 0
    return ActorsPage(
      rows: results.compactMap { row in
        guard let person = row[personIndex] else { return nil }
        return ActorRow(person: person)
      },
      columns: columns,
      hasMore: body["hasMore"]?.boolValue ?? false,
      hogql: body["hogql"]?.stringValue,
      missingActorsCount: body["missing_actors_count"]?.intValue ?? 0
    )
  }
}
