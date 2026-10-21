import Foundation
import PostHogFoundation

/// A feature flag. `name` is the human description (the key is the identifier);
/// `filters` stays raw — release conditions render read-only in Phase 1.
public struct FeatureFlag: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let key: String
  public let name: String
  public let active: Bool
  public let deleted: Bool
  public let filters: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case key
    case name
    case active
    case deleted
    case filters
  }

  public init(id: Int, key: String, name: String, active: Bool, deleted: Bool, filters: JSONValue?) {
    self.id = id
    self.key = key
    self.name = name
    self.active = active
    self.deleted = deleted
    self.filters = filters
  }

  /// "100%", "34% of users", or "3 variants" — the list-row summary.
  public var rolloutSummary: String {
    let groups = filters?["groups"]?.arrayValue ?? []
    if let variants = filters?["multivariate"]?["variants"]?.arrayValue, !variants.isEmpty {
      return "\(variants.count) variants"
    }
    guard !groups.isEmpty else { return "No conditions" }
    let percentages = groups.map { $0["rollout_percentage"]?.numberValue ?? 100 }
    if let single = percentages.first, groups.count == 1 {
      return single >= 100 ? "100% of users" : "\(Int(single))% of users"
    }
    return "\(groups.count) condition sets"
  }

  public var conditionGroups: [JSONValue] {
    filters?["groups"]?.arrayValue ?? []
  }
}

/// The person behind an activity-log entry.
public struct ActivityActor: Codable, Sendable, Equatable {
  public let firstName: String?
  public let email: String?

  enum CodingKeys: String, CodingKey {
    case firstName = "first_name"
    case email
  }
}

/// One activity-log entry for a flag (who changed what, when).
public struct ActivityLogEntry: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let activity: String
  public let createdAt: Date
  public let user: ActivityActor?
  public let detail: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case activity
    case createdAt = "created_at"
    case user
    case detail
  }

  public var actorName: String {
    if let name = user?.firstName, !name.isEmpty { return name }
    return user?.email ?? "Someone"
  }
}

extension APIClient {
  public func featureFlags(
    projectID: Int,
    search: String? = nil,
    active: Bool? = nil,
    limit: Int = 100
  ) async throws -> Paginated<FeatureFlag> {
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    if let search, !search.isEmpty {
      query.append(URLQueryItem(name: "search", value: search))
    }
    if let active {
      query.append(URLQueryItem(name: "active", value: active ? "true" : "false"))
    }
    return try await send(.get("/api/projects/\(projectID)/feature_flags/", query: query))
  }

  public func featureFlag(projectID: Int, flagID: Int) async throws -> FeatureFlag {
    try await send(.get("/api/projects/\(projectID)/feature_flags/\(flagID)/"))
  }

  /// The purpose-built toggle endpoints — never a hand-rolled PATCH of filters.
  public func setFeatureFlag(projectID: Int, flagID: Int, enabled: Bool) async throws -> FeatureFlag {
    let path =
      enabled
      ? "/api/projects/\(projectID)/feature_flags/\(flagID)/enable/"
      : "/api/projects/\(projectID)/feature_flags/\(flagID)/disable/"
    return try await send(.post(path))
  }

  public func featureFlagActivity(projectID: Int, flagID: Int) async throws -> Paginated<ActivityLogEntry> {
    try await send(.get("/api/projects/\(projectID)/feature_flags/\(flagID)/activity/"))
  }
}
