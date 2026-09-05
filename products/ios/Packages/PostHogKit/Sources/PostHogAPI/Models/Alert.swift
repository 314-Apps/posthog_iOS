import Foundation
import PostHogFoundation

/// An insight alert. The API returns `insight` as an ID or a nested object, and
/// bounds nest under `threshold.configuration.bounds`; both decode defensively.
/// `thresholdRaw` keeps the whole threshold so writes can round-trip fields this
/// client does not model.
public struct InsightAlert: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let enabled: Bool
  public let insightID: Int?
  public let state: String?
  public let calculationInterval: String?
  public let lowerThreshold: Double?
  public let upperThreshold: Double?
  public let thresholdRaw: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case enabled
    case insight
    case state
    case calculationInterval = "calculation_interval"
    case threshold
  }

  public init(
    id: String,
    name: String,
    enabled: Bool,
    insightID: Int?,
    state: String?,
    calculationInterval: String?,
    lowerThreshold: Double?,
    upperThreshold: Double?,
    thresholdRaw: JSONValue?
  ) {
    self.id = id
    self.name = name
    self.enabled = enabled
    self.insightID = insightID
    self.state = state
    self.calculationInterval = calculationInterval
    self.lowerThreshold = lowerThreshold
    self.upperThreshold = upperThreshold
    self.thresholdRaw = thresholdRaw
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    let insight = try container.decodeIfPresent(JSONValue.self, forKey: .insight)
    insightID = insight?.intValue ?? insight?["id"]?.intValue
    state = try container.decodeIfPresent(String.self, forKey: .state)
    calculationInterval = try container.decodeIfPresent(String.self, forKey: .calculationInterval)
    let threshold = try container.decodeIfPresent(JSONValue.self, forKey: .threshold)
    thresholdRaw = threshold
    let bounds = threshold?["configuration"]?["bounds"]
    lowerThreshold = bounds?["lower"]?.numberValue
    upperThreshold = bounds?["upper"]?.numberValue
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(enabled, forKey: .enabled)
    try container.encodeIfPresent(insightID, forKey: .insight)
    try container.encodeIfPresent(state, forKey: .state)
    try container.encodeIfPresent(calculationInterval, forKey: .calculationInterval)
    try container.encodeIfPresent(thresholdRaw, forKey: .threshold)
  }

  // swiftlint:disable function_parameter_count
  /// The write payload for create and update. Bounds keys stay absent when nil
  /// so the server clears a bound the user removed instead of keeping it.
  public static func payload(
    name: String,
    enabled: Bool,
    insightID: Int,
    calculationInterval: String,
    lower: Double?,
    upper: Double?
  ) -> Data {
    // swiftlint:enable function_parameter_count
    var bounds: [String: JSONValue] = [:]
    if let lower { bounds["lower"] = .number(lower) }
    if let upper { bounds["upper"] = .number(upper) }
    let payload: JSONValue = .object([
      "name": .string(name),
      "enabled": .bool(enabled),
      "insight": .number(Double(insightID)),
      "calculation_interval": .string(calculationInterval),
      "threshold": .object([
        "configuration": .object([
          "type": .string("absolute"),
          "bounds": .object(bounds),
        ])
      ]),
      "subscribed_users": .array([]),
      "config": .object([
        "type": .string("TrendsAlertConfig"),
        "series_index": .number(0),
      ]),
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Encoding a JSONValue tree cannot fail; the fallback only satisfies the type.
    return (try? encoder.encode(payload)) ?? Data()
  }
}

extension APIClient {
  /// Lists alerts; `insightID` narrows server-side via `insight_id`. Callers
  /// still filter by insight because older servers ignore unknown params.
  public func insightAlerts(projectID: Int, insightID: Int? = nil) async throws -> Paginated<InsightAlert> {
    var query: [URLQueryItem] = []
    if let insightID {
      query.append(URLQueryItem(name: "insight_id", value: String(insightID)))
    }
    return try await send(.get("/api/projects/\(projectID)/alerts/", query: query))
  }

  public func createInsightAlert(projectID: Int, body: Data) async throws -> InsightAlert {
    try await send(.post("/api/projects/\(projectID)/alerts/", body: body))
  }

  public func updateInsightAlert(projectID: Int, alertID: String, body: Data) async throws -> InsightAlert {
    try await send(.patch("/api/projects/\(projectID)/alerts/\(alertID)/", body: body))
  }

  public func deleteInsightAlert(projectID: Int, alertID: String) async throws {
    try await sendRaw(.delete("/api/projects/\(projectID)/alerts/\(alertID)/"))
  }
}
