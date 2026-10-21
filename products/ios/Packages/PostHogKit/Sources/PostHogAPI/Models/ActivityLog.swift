import Foundation

/// One row of the project-wide activity log. `ActivityLogEntry` predates this
/// model and drops the top-level `scope` the project feed groups by, so the
/// feed decodes rows into this shape instead.
public struct ProjectActivityEntry: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let activity: String
  public let scope: String?
  public let createdAt: Date
  public let user: ActivityActor?

  enum CodingKeys: String, CodingKey {
    case id
    case activity
    case scope
    case createdAt = "created_at"
    case user
  }

  public init(id: String, activity: String, scope: String?, createdAt: Date, user: ActivityActor?) {
    self.id = id
    self.activity = activity
    self.scope = scope
    self.createdAt = createdAt
    self.user = user
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.activity = try container.decodeIfPresent(String.self, forKey: .activity) ?? ""
    self.scope = try container.decodeIfPresent(String.self, forKey: .scope)
    // Missing timestamps sort deterministically into the oldest bucket.
    self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    self.user = try container.decodeIfPresent(ActivityActor.self, forKey: .user)
  }

  public var actorName: String {
    if let name = user?.firstName, !name.isEmpty { return name }
    return user?.email ?? "Someone"
  }
}

extension APIClient {
  /// The first-page request; the feed streams later pages via `pages(startingAt:)`.
  public static func activityLogRequest(projectID: Int, scope: String? = nil) -> APIRequest {
    var query: [URLQueryItem] = []
    if let scope, !scope.isEmpty {
      query.append(URLQueryItem(name: "scope", value: scope))
    }
    return .get("/api/projects/\(projectID)/activity_log/", query: query)
  }

  public func activityLog(projectID: Int, scope: String? = nil) async throws -> Paginated<ProjectActivityEntry> {
    try await send(Self.activityLogRequest(projectID: projectID, scope: scope))
  }
}
