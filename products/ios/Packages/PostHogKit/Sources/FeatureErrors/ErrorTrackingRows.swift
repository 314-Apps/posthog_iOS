import Foundation
import PostHogAPI
import PostHogFoundation

/// One list row from an ErrorTrackingQuery response. Codable so the list can
/// snapshot rows into the disk cache.
struct ErrorTrackingRow: Codable, Sendable, Equatable, Identifiable {
  let id: String
  let name: String?
  let description: String?
  let status: ErrorTrackingIssue.Status
  let occurrences: Double
  let sessions: Double
  let users: Double
  let firstSeen: Date?
  let lastSeen: Date?
  let volume: [Double]

  var displayTitle: String {
    name ?? description ?? "Untitled issue"
  }

  /// Nil when the description already stands in for a missing name.
  var displaySubtitle: String? {
    name == nil ? nil : description
  }
}

/// Maps the `QueryResult.unknown` body of an ErrorTrackingQuery run.
/// ErrorTrackingQuery is not a modeled query kind, so the shape is read
/// defensively — rows without an id are dropped, everything else defaults.
enum ErrorTrackingRows {
  static func parse(_ body: JSONValue) -> [ErrorTrackingRow] {
    guard let results = body["results"]?.arrayValue else { return [] }
    return results.compactMap(row(from:))
  }

  private static func row(from raw: JSONValue) -> ErrorTrackingRow? {
    guard let object = raw.objectValue, let id = object["id"]?.stringValue else { return nil }
    return ErrorTrackingRow(
      id: id,
      name: object["name"]?.stringValue,
      description: object["description"]?.stringValue,
      status: object["status"]?.stringValue.flatMap(ErrorTrackingIssue.Status.init(rawValue:)) ?? .unknown,
      occurrences: count("occurrences", in: object),
      sessions: count("sessions", in: object),
      users: count("users", in: object),
      firstSeen: date(object["first_seen"]),
      lastSeen: date(object["last_seen"]),
      volume: volume(in: object)
    )
  }

  /// Counts and volume arrive top-level or nested under `aggregations`
  /// depending on the server version; accept both.
  private static func count(_ key: String, in object: [String: JSONValue]) -> Double {
    object[key]?.numberValue ?? object["aggregations"]?[key]?.numberValue ?? 0
  }

  private static func volume(in object: [String: JSONValue]) -> [Double] {
    let values = object["volume"]?.arrayValue ?? object["aggregations"]?["volume"]?.arrayValue ?? []
    return values.compactMap(\.numberValue)
  }

  private static func date(_ value: JSONValue?) -> Date? {
    guard let string = value?.stringValue else { return nil }
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    return (try? Date(string, strategy: fractional)) ?? (try? Date(string, strategy: .iso8601))
  }
}
