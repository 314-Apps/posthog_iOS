import Foundation
import PostHogFoundation

/// An A/B experiment. Metrics and parameters stay raw — result analysis renders
/// on the web, so this client only derives lifecycle and variant counts from them.
public struct Experiment: Codable, Sendable, Equatable, Identifiable {
  /// Derived from the date pair; the API has no single status field.
  public enum Lifecycle: Sendable, Equatable {
    case draft
    case running
    case complete
  }

  public let id: Int
  public let name: String
  public let description: String?
  public let startDate: Date?
  public let endDate: Date?
  public let archived: Bool
  public let featureFlagKey: String?
  public let metricsRaw: JSONValue?
  public let parametersRaw: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case startDate = "start_date"
    case endDate = "end_date"
    case archived
    case featureFlagKey = "feature_flag_key"
    case featureFlag = "feature_flag"
    case metricsRaw = "metrics"
    case parametersRaw = "parameters"
  }

  public init(
    id: Int,
    name: String,
    description: String? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil,
    archived: Bool = false,
    featureFlagKey: String? = nil,
    metricsRaw: JSONValue? = nil,
    parametersRaw: JSONValue? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.startDate = startDate
    self.endDate = endDate
    self.archived = archived
    self.featureFlagKey = featureFlagKey
    self.metricsRaw = metricsRaw
    self.parametersRaw = parametersRaw
  }

  /// The API serializes the linked flag two ways: a `feature_flag_key` string or
  /// a nested `feature_flag` object. Decode both; a malformed shape means no key.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    startDate = try? container.decode(Date.self, forKey: .startDate)
    endDate = try? container.decode(Date.self, forKey: .endDate)
    archived = (try? container.decode(Bool.self, forKey: .archived)) ?? false
    if let key = try? container.decode(String.self, forKey: .featureFlagKey) {
      featureFlagKey = key
    } else if let flag = try? container.decode(JSONValue.self, forKey: .featureFlag) {
      featureFlagKey = flag["key"]?.stringValue
    } else {
      featureFlagKey = nil
    }
    metricsRaw = try container.decodeIfPresent(JSONValue.self, forKey: .metricsRaw)
    parametersRaw = try container.decodeIfPresent(JSONValue.self, forKey: .parametersRaw)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(startDate, forKey: .startDate)
    try container.encodeIfPresent(endDate, forKey: .endDate)
    try container.encode(archived, forKey: .archived)
    try container.encodeIfPresent(featureFlagKey, forKey: .featureFlagKey)
    try container.encodeIfPresent(metricsRaw, forKey: .metricsRaw)
    try container.encodeIfPresent(parametersRaw, forKey: .parametersRaw)
  }

  public var lifecycle: Lifecycle {
    guard startDate != nil else { return .draft }
    return endDate == nil ? .running : .complete
  }

  /// Variant count from `parameters.feature_flag_variants`; nil when the
  /// parameters are absent or not shaped as expected.
  public var variantCount: Int? {
    parametersRaw?["feature_flag_variants"]?.arrayValue?.count
  }
}

extension APIClient {
  public func experiments(projectID: Int, limit: Int = 100) async throws -> Paginated<Experiment> {
    try await send(
      .get(
        "/api/projects/\(projectID)/experiments/",
        query: [URLQueryItem(name: "limit", value: String(limit))]
      ))
  }

  public func experiment(projectID: Int, experimentID: Int) async throws -> Experiment {
    try await send(.get("/api/projects/\(projectID)/experiments/\(experimentID)/"))
  }
}
