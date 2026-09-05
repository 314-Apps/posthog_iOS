import Foundation
import PostHogFoundation

/// Saved insight (list row and detail share one shape).
public struct Insight: Codable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let shortID: String
  public let name: String?
  public let derivedName: String?
  public let description: String?
  public let favorited: Bool
  public let query: JSONValue?
  public let result: JSONValue?

  enum CodingKeys: String, CodingKey {
    case id
    case shortID = "short_id"
    case name
    case derivedName = "derived_name"
    case description
    case favorited
    case query
    case result
  }

  public var displayName: String {
    if let name, !name.isEmpty { return name }
    return derivedName ?? "Untitled insight"
  }
}

extension APIClient {
  public func insights(
    projectID: Int,
    search: String? = nil,
    limit: Int = 50,
    offset: Int = 0
  ) async throws -> Paginated<Insight> {
    var query = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "offset", value: String(offset)),
      URLQueryItem(name: "saved", value: "true"),
      URLQueryItem(name: "order", value: "-last_modified_at"),
    ]
    if let search, !search.isEmpty {
      query.append(URLQueryItem(name: "search", value: search))
    }
    return try await send(.get("/api/projects/\(projectID)/insights/", query: query))
  }

  public func insight(projectID: Int, insightID: Int) async throws -> Insight {
    try await send(.get("/api/projects/\(projectID)/insights/\(insightID)/"))
  }
}
