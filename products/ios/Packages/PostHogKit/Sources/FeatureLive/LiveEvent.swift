import Foundation
import PostHogFoundation

/// One event from the livestream tail. The stream carries no stable
/// identifier, so `id` is minted locally when the event decodes.
public struct LiveEvent: Identifiable, Sendable, Equatable {
  public let id: UUID
  public let event: String
  public let distinctID: String
  public let timestamp: Date?
  public let properties: JSONValue

  public init(
    id: UUID = UUID(),
    event: String,
    distinctID: String,
    timestamp: Date?,
    properties: JSONValue
  ) {
    self.id = id
    self.event = event
    self.distinctID = distinctID
    self.timestamp = timestamp
    self.properties = properties
  }
}

extension LiveEvent {
  private static let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let plainISO = Date.ISO8601FormatStyle()

  /// Decodes one SSE `data` payload. Anything that is not a JSON object with
  /// string `event` and `distinct_id` fields returns nil, so junk lines drop
  /// silently instead of poisoning the feed.
  init?(sseData: String) {
    guard
      let data = sseData.data(using: .utf8),
      let json = try? JSONDecoder().decode(JSONValue.self, from: data),
      let event = json["event"]?.stringValue,
      let distinctID = json["distinct_id"]?.stringValue
    else { return nil }
    self.init(
      event: event,
      distinctID: distinctID,
      timestamp: (json["timestamp"]?.stringValue).flatMap(Self.parseTimestamp),
      properties: Self.normalizedProperties(json["properties"])
    )
  }

  private static func parseTimestamp(_ raw: String) -> Date? {
    if let date = try? Date(raw, strategy: fractionalISO) { return date }
    return try? Date(raw, strategy: plainISO)
  }

  /// The livestream serializes `properties` either as a JSON object or as a
  /// string that itself contains JSON; both shapes must land as one value.
  private static func normalizedProperties(_ raw: JSONValue?) -> JSONValue {
    guard let raw else { return .object([:]) }
    guard
      let text = raw.stringValue,
      let data = text.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return raw }
    return decoded
  }
}
